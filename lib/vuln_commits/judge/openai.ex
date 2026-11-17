defmodule VulnCommits.Judge.OpenAI do
  alias VulnCommits.Judge.Prompt

  @url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4.1-mini-2025-04-14"
  @default_backoff_ms 500
  @max_attempts 5
  @price_input 0.40
  @price_output 1.60

  def judge(system, user, opts) do
    key = System.get_env("OPENAI_API_KEY")

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

  defp payload(system, user, opts) do
    %{
      model: Keyword.get(opts, :model, default_model()),
      temperature: 0,
      seed: Keyword.fetch!(opts, :seed),
      messages: [
        %{role: "system", content: system},
        %{role: "user", content: user}
      ],
      response_format: %{
        type: "json_schema",
        json_schema: %{name: "judgment", strict: true, schema: Prompt.schema()}
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
    base_options = [json: payload, auth: {:bearer, key}, retry: false, receive_timeout: 60_000]
    extra_options = Application.get_env(:vuln_commits, :openai_req_options, [])
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

  defp read_judgment(%{"choices" => [%{"message" => %{"content" => content}} | _]} = body) do
    usage = Map.get(body, "usage", %{})
    judgment(content, usage)
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
        avg_output_tokens \\ 80,
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

  defp default_model, do: System.get_env("OPENAI_MODEL", @default_model)
end
