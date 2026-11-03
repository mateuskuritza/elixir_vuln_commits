# testes do cliente openai com o Req.Test no lugar da rede
defmodule VulnCommits.Judge.OpenAITest do
  use ExUnit.Case, async: false

  alias VulnCommits.Judge.OpenAI

  @content_ok ~s({"label":"VULNERABLE","cia":"availability","reason":"fixes crash"})

  setup do
    System.put_env("OPENAI_API_KEY", "sk-teste")
    System.delete_env("OPENAI_MODEL")
    on_exit(fn -> System.delete_env("OPENAI_API_KEY") end)
    :ok
  end

  # resposta no formato do chat completions com o conteúdo dado
  defp completion(content) do
    %{
      "choices" => [%{"message" => %{"role" => "assistant", "content" => content}}],
      "usage" => %{"prompt_tokens" => 10, "completion_tokens" => 5}
    }
  end

  defp judge(opts \\ []) do
    OpenAI.judge("system", "user", Keyword.merge([seed: 1, backoff_ms: 0], opts))
  end

  test "judge devolve rótulo, cia, motivo e uso" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      Req.Test.json(conn, completion(@content_ok))
    end)

    assert {:ok, %{label: :vulnerable, cia: "availability", reason: "fixes crash"} = result} =
             judge()

    assert result.usage == %{"prompt_tokens" => 10, "completion_tokens" => 5}
    assert result.raw["label"] == "VULNERABLE"
  end

  test "conteúdo que não é json devolve bad_json sem tentar de novo" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      Process.put(:calls, Process.get(:calls, 0) + 1)
      Req.Test.json(conn, completion("not json"))
    end)

    assert {:error, {:bad_json, "not json"}} = judge()
    assert Process.get(:calls) == 1
  end

  test "label fora do enum também é bad_json" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      Req.Test.json(conn, completion(~s({"label":"MAYBE","cia":"none","reason":"x"})))
    end)

    assert {:error, {:bad_json, _}} = judge()
  end

  test "429 nas duas primeiras chamadas e 200 na terceira dá sucesso" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      n = Process.get(:calls, 0) + 1
      Process.put(:calls, n)

      if n <= 2 do
        conn |> Plug.Conn.put_status(429) |> Req.Test.json(%{"error" => "rate limit"})
      else
        Req.Test.json(conn, completion(@content_ok))
      end
    end)

    assert {:ok, %{label: :vulnerable}} = judge()
    assert Process.get(:calls) == 3
  end

  test "500 sempre esgota em 5 tentativas" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      Process.put(:calls, Process.get(:calls, 0) + 1)
      conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{"error" => "boom"})
    end)

    assert {:error, {:http, 500, _}} = judge()
    assert Process.get(:calls) == 5
  end

  test "erro de transporte é tentado de novo" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      n = Process.get(:calls, 0) + 1
      Process.put(:calls, n)

      if n == 1 do
        Req.Test.transport_error(conn, :timeout)
      else
        Req.Test.json(conn, completion(@content_ok))
      end
    end)

    assert {:ok, _} = judge()
    assert Process.get(:calls) == 2
  end

  test "4xx que não é 429 volta na hora, sem retry" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      Process.put(:calls, Process.get(:calls, 0) + 1)
      conn |> Plug.Conn.put_status(400) |> Req.Test.json(%{"error" => "bad request"})
    end)

    assert {:error, {:http, 400, %{"error" => "bad request"}}} = judge()
    assert Process.get(:calls) == 1
  end

  test "corpo da requisição leva temperature 0, seed, modelo e json_schema strict" do
    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      Process.put(:body, Jason.decode!(raw))
      Req.Test.json(conn, completion(@content_ok))
    end)

    assert {:ok, _} = judge(seed: 7)

    body = Process.get(:body)
    assert body["model"] == "gpt-4.1-mini-2025-04-14"
    assert body["temperature"] == 0
    assert body["seed"] == 7

    assert body["messages"] == [
             %{"role" => "system", "content" => "system"},
             %{"role" => "user", "content" => "user"}
           ]

    assert body["response_format"]["type"] == "json_schema"
    assert body["response_format"]["json_schema"]["strict"] == true
    assert body["response_format"]["json_schema"]["name"] == "judgment"
  end

  test "OPENAI_MODEL sobrescreve o modelo padrão" do
    System.put_env("OPENAI_MODEL", "outro-modelo")
    on_exit(fn -> System.delete_env("OPENAI_MODEL") end)

    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      {:ok, raw, conn} = Plug.Conn.read_body(conn)
      Process.put(:body, Jason.decode!(raw))
      Req.Test.json(conn, completion(@content_ok))
    end)

    assert {:ok, _} = judge()
    assert Process.get(:body)["model"] == "outro-modelo"
  end

  test "sem OPENAI_API_KEY devolve missing_api_key sem chamar a api" do
    System.delete_env("OPENAI_API_KEY")

    Req.Test.stub(VulnCommits.Judge.OpenAI, fn conn ->
      Process.put(:calls, Process.get(:calls, 0) + 1)
      Req.Test.json(conn, completion(@content_ok))
    end)

    assert {:error, :missing_api_key} = judge()
    assert Process.get(:calls, 0) == 0
  end

  test "estimate_cost usa a tabela de preços do modelo" do
    assert_in_delta OpenAI.estimate_cost(10_000, 4000, 80, "gpt-4.1-mini-2025-04-14"),
                    17.28,
                    1.0e-9
  end

  test "estimate_cost de modelo desconhecido devolve nil" do
    assert OpenAI.estimate_cost(10, 4000, 80, "modelo-inexistente") == nil
  end
end
