# cliente da openai: chat completions com saída estruturada e retry
defmodule VulnCommits.Judge.OpenAI do
  alias VulnCommits.Judge.Prompt

  @url "https://api.openai.com/v1/chat/completions"
  @default_model "gpt-4.1-mini-2025-04-14"
  @default_backoff_ms 500
  @max_attempts 5

  # preços de referência de 2025, conferir antes de rodar (US$ por milhão de tokens: entrada, saída)
  @prices %{
    "gpt-4.1-mini-2025-04-14" => {0.40, 1.60}
  }

  # julga um commit; opts: seed (obrigatória), model e backoff_ms
  def judge(system, user, opts) do
    case System.get_env("OPENAI_API_KEY") do
      key when key in [nil, ""] ->
        {:error, :missing_api_key}

      key ->
        payload = payload(system, user, opts)
        backoff_ms = Keyword.get(opts, :backoff_ms, @default_backoff_ms)

        with {:ok, body} <- attempt(fn -> post(key, payload) end, 1, backoff_ms) do
          read_judgment(body)
        end
    end
  end

  # corpo do pedido: temperature 0 e seed fixa para a execução ser repetível
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

  # tenta de novo só em 429, 5xx e erro de transporte, com espera 2^(n-1) * backoff_ms
  defp attempt(fun, n, backoff_ms) do
    case fun.() do
      {:retry, _reason} when n < @max_attempts ->
        Process.sleep(round(:math.pow(2, n - 1) * backoff_ms))
        attempt(fun, n + 1, backoff_ms)

      {:retry, reason} ->
        {:error, reason}

      other ->
        other
    end
  end

  # uma chamada http; o retry do próprio Req fica desligado (quem tenta de novo é o attempt)
  defp post(key, payload) do
    options =
      [json: payload, auth: {:bearer, key}, retry: false] ++
        Application.get_env(:vuln_commits, :openai_req_options, [])

    case Req.post(@url, options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} when status == 429 or status >= 500 ->
        {:retry, {:http, status, body}}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:http, status, body}}

      {:error, reason} ->
        {:retry, reason}
    end
  end

  # pega o conteúdo da primeira escolha e o uso de tokens da resposta
  defp read_judgment(%{"choices" => [%{"message" => %{"content" => content}} | _]} = body) do
    judgment(content, Map.get(body, "usage", %{}))
  end

  defp read_judgment(body), do: {:error, {:bad_json, body}}

  # o conteúdo tem que ser json com um label válido; senão é bad_json, sem retry
  defp judgment(content, usage) do
    with {:ok, %{"label" => label} = raw} <- Jason.decode(content),
         {:ok, label} <- parse_label(label) do
      {:ok,
       %{
         label: label,
         cia: raw["cia"],
         reason: raw["reason"],
         raw: raw,
         usage: usage
       }}
    else
      _ -> {:error, {:bad_json, content}}
    end
  end

  defp parse_label("VULNERABLE"), do: {:ok, :vulnerable}
  defp parse_label("NEUTRAL"), do: {:ok, :neutral}
  defp parse_label(_), do: :error

  # custo estimado em US$ para n chamadas com a média de tokens dada; nil se o modelo não tem preço
  def estimate_cost(
        n_calls,
        avg_input_tokens \\ 4000,
        avg_output_tokens \\ 80,
        model \\ default_model()
      ) do
    case Map.fetch(@prices, model) do
      {:ok, {price_in, price_out}} ->
        n_calls * (avg_input_tokens * price_in + avg_output_tokens * price_out) / 1_000_000

      :error ->
        nil
    end
  end

  # modelo usado quando não se passa um: OPENAI_MODEL ou o snapshot padrão
  def model, do: default_model()

  defp default_model, do: System.get_env("OPENAI_MODEL", @default_model)
end
