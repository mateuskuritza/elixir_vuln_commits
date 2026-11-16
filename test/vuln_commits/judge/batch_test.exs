defmodule VulnCommits.Judge.BatchTest do
  use ExUnit.Case, async: true
  alias VulnCommits.Commit
  alias VulnCommits.Judge.{Batch, Store}

  defp commit(hash),
    do: %Commit{
      hash: hash,
      repo: "r",
      date: ~D[2015-01-01],
      message: "fix crash",
      files: ["a.ex"]
    }

  setup do
    dir = Path.join(System.tmp_dir!(), "batch_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(dir) end)
    %{dir: dir}
  end

  test "export divide em lotes com o prompt do sistema e um bloco por commit", %{dir: dir} do
    batches =
      Batch.export(Enum.map(~w(h1 h2 h3), &commit/1), dir,
        batch_size: 2,
        version: "v1",
        diff_fun: fn _ -> "+x" end
      )

    assert Enum.map(batches, & &1.hashes) == [["h1", "h2"], ["h3"]]
    text = File.read!(hd(batches).path)
    assert text =~ "=== COMMIT h1 ==="
    assert text =~ "=== COMMIT h2 ==="
    assert text =~ "VULNERABLE if its message and changes"
  end

  test "parse aceita linhas validas e ignora texto em volta" do
    out = """
    aqui estao:
    {"hash": "h1", "label": "VULNERABLE", "cia": "availability", "reason": "crash"}
    {"hash": "h2", "label": "NEUTRAL", "cia": "none", "reason": "docs"}
    """

    assert {:ok, [%{"hash" => "h1"}, %{"hash" => "h2"}]} = Batch.parse(out, ["h1", "h2"])
  end

  test "parse acusa hash faltando e linha invalida" do
    out = ~s({"hash": "h1", "label": "MAYBE", "cia": "none", "reason": "?"})
    assert {:error, %{invalid: 1, missing: ["h1", "h2"]}} = Batch.parse(out, ["h1", "h2"])
  end

  test "store grava no formato do jsonl com run, modelo e versao", %{dir: dir} do
    path = Path.join(dir, "j.jsonl")
    j = [%{"hash" => "h1", "label" => "NEUTRAL", "cia" => "none", "reason" => "ok"}]
    Batch.store(j, %{"h1" => commit("h1")}, path, run: 2, model: "m", version: "v1")

    assert [%{hash: "h1", run: 2, model: "m", prompt_version: "v1", label: "NEUTRAL"}] =
             Store.load(path)
  end
end
