defmodule VulnCommits.Judge.StoreTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Judge.Store

  setup do
    path =
      Path.join(
        System.tmp_dir!(),
        "store_test_#{System.unique_integer([:positive])}/judgments.jsonl"
      )

    on_exit(fn -> File.rm_rf(Path.dirname(path)) end)
    %{path: path}
  end

  defp record(hash, run, label, opts \\ []) do
    %{
      hash: hash,
      repo: Keyword.get(opts, :repo, "org/repo"),
      run: run,
      model: Keyword.get(opts, :model, "claude-opus-5-5"),
      prompt_version: Keyword.get(opts, :prompt_version, "v1"),
      label: label,
      cia: "availability",
      reason: "fixes crash",
      error: nil,
      usage: %{"prompt_tokens" => 10},
      judged_at: "2026-10-21T12:00:00Z"
    }
  end

  test "append de 2 registros e load devolve os 2 na ordem", %{path: path} do
    r1 = record("a1", 1, "VULNERABLE")
    r2 = record("a1", 2, "NEUTRAL")

    assert :ok = Store.append(path, r1)
    assert :ok = Store.append(path, r2)

    assert [loaded1, loaded2] = Store.load(path)
    assert loaded1 == %{r1 | usage: %{prompt_tokens: 10}}
    assert loaded2 == %{r2 | usage: %{prompt_tokens: 10}}
  end

  test "append cria o diretorio pai quando nao existe", %{path: path} do
    refute File.exists?(Path.dirname(path))
    assert :ok = Store.append(path, record("a1", 1, "NEUTRAL"))
    assert File.exists?(path)
  end

  test "load de arquivo inexistente e lista vazia", %{path: path} do
    assert Store.load(path) == []
  end

  test "load usa atomos nas chaves e pula linhas vazias", %{path: path} do
    Store.append(path, record("a1", 1, "VULNERABLE"))
    File.write!(path, "\n", [:append])
    Store.append(path, record("b2", 1, "NEUTRAL"))

    assert [%{hash: "a1", label: "VULNERABLE"}, %{hash: "b2", label: "NEUTRAL"}] =
             Store.load(path)
  end

  test "done ignora ERROR", %{path: path} do
    records = [
      record("a1", 1, "VULNERABLE"),
      record("a1", 2, "ERROR"),
      record("b2", 1, "NEUTRAL")
    ]

    Enum.each(records, &Store.append(path, &1))

    assert Store.done(Store.load(path)) ==
             MapSet.new([
               {"a1", 1, "claude-opus-5-5", "v1"},
               {"b2", 1, "claude-opus-5-5", "v1"}
             ])
  end

  test "by_commit agrupa, ordena por run e ignora outro prompt_version" do
    records = [
      record("a1", 2, "NEUTRAL"),
      record("a1", 1, "VULNERABLE"),
      record("a1", 3, "VULNERABLE", prompt_version: "v2"),
      record("b2", 1, "ERROR"),
      record("b2", 2, "NEUTRAL")
    ]

    assert Store.by_commit(records, "claude-opus-5-5", "v1") == %{
             "a1" => [:vulnerable, :neutral],
             "b2" => [:neutral]
           }
  end

  test "by_commit ignora outro modelo" do
    records = [
      record("a1", 1, "VULNERABLE", model: "gpt-4o-2024-08-06"),
      record("a1", 2, "NEUTRAL", model: "claude-opus-5-5"),
      record("b2", 1, "VULNERABLE", model: "gpt-4o-2024-08-06")
    ]

    assert Store.by_commit(records, "claude-opus-5-5", "v1") == %{
             "a1" => [:neutral]
           }
  end

  test "by_commit com {hash, run} repetido mantem o ultimo do arquivo" do
    records = [
      record("a1", 1, "VULNERABLE"),
      record("a1", 2, "NEUTRAL"),
      record("a1", 1, "NEUTRAL")
    ]

    assert Store.by_commit(records, "claude-opus-5-5", "v1") == %{
             "a1" => [:neutral, :neutral]
           }
  end
end
