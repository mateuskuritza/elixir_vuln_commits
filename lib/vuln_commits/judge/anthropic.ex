defmodule VulnCommits.Judge.Anthropic do
  # juiz pela api da anthropic (messages api, http direto com req, não tem sdk oficial em elixir).
  # mesmo modelo dos agentes, então os julgamentos dos dois caminhos ficam comparáveis.
  alias VulnCommits.Judge.Batch
  alias VulnCommits.Judge.Prompt

  @url "https://api.anthropic.com/v1/messages"
  @api_version "2026-10-21"
  @default_model "claude-opus-5-5"
  @default_backoff_ms 500
  @max_attempts 5
  # us$ por milhão de tokens do claude-opus-5-5
  @price_input 4.0
  @price_output 20.0

  def judge(system, user, opts) do
    key = System.get_env("ANTHROPIC_API_KEY")

    if key == nil or key == "" do
      {:error, :missing_api_key}
    else
      payload = payload(system, user, opts)
      backoff_ms = Keyword.get(opts, :backoff_ms, @default_backoff_ms)
      post_once = fn -> post(key, payload) end

      case attempt(post_once, 1, backoff_ms) do
        {:ok, body} -> read_judgment(body)
        other -> other
      end
    end
  end

  # sem temperature nem seed: o modelo não aceita. a variação entre execuções é medida pelo kappa
  defp payload(system, user, opts) do
    %{
      model: Keyword.get(opts, :model, default_model()),
      max_tokens: 4096,
      system: system,
      messages: [%{role: "user", content: user}],
      output_config: %{
        effort: "medium",
        format: %{type: "json_schema", schema: Prompt.schema()}
      }
    }
  end

  defp attempt(post_once, number, backoff_ms) do
    case post_once.() do
      {:retry, reason} ->
        if number < @max_attempts do
          wait_ms = round(:math.pow(2, number - 1) * backoff_ms)
          Process.sleep(wait_ms)
          attempt(post_once, number + 1, backoff_ms)
        else
          {:error, reason}
        end

      other ->
        other
    end
  end

  defp post(key, payload) do
    headers = [{"x-api-key", key}, {"anthropic-version", @api_version}]
    base_options = [json: payload, headers: headers, retry: false, receive_timeout: 120_000]
    extra_options = Application.get_env(:vuln_commits, :anthropic_req_options, [])
    options = base_options ++ extra_options

    case Req.post(@url, options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        if status == 429 or status >= 500 do
          {:retry, {:http, status, body}}
        else
          {:error, {:http, status, body}}
        end

      {:error, reason} ->
        {:retry, reason}
    end
  end

  defp read_judgment(%{"stop_reason" => "refusal"} = body), do: {:error, {:refusal, body}}

  defp read_judgment(%{"content" => blocks} = body) when is_list(blocks) do
    usage = Map.get(body, "usage", %{})

    case Enum.find(blocks, fn block -> block["type"] == "text" end) do
      %{"text" => text} -> judgment(text, usage)
      nil -> {:error, {:bad_json, body}}
    end
  end

  defp read_judgment(body), do: {:error, {:bad_json, body}}

  defp judgment(content, usage) do
    case Jason.decode(content) do
      {:ok, %{"label" => label_text} = raw} ->
        case parse_label(label_text) do
          {:ok, label} ->
            {:ok,
             %{
               label: label,
               cia: raw["cia"],
               reason: raw["reason"],
               raw: raw,
               usage: usage
             }}

          :error ->
            {:error, {:bad_json, content}}
        end

      _other ->
        {:error, {:bad_json, content}}
    end
  end

  defp parse_label("VULNERABLE"), do: {:ok, :vulnerable}
  defp parse_label("NEUTRAL"), do: {:ok, :neutral}
  defp parse_label(_), do: :error

  def estimate_cost(
        n_calls,
        avg_input_tokens \\ 4000,
        avg_output_tokens \\ 300,
        model \\ default_model()
      ) do
    if model == @default_model do
      input_cost = avg_input_tokens * @price_input
      output_cost = avg_output_tokens * @price_output
      n_calls * (input_cost + output_cost) / 1_000_000
    else
      nil
    end
  end

  def model, do: default_model()

  # mesmo JUDGE_MODEL do caminho por agentes
  defp default_model, do: Batch.model()
end
