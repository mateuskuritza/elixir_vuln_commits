# testes da orquestracao: candidatos, pendentes, execucao com juiz falso e rotulos
defmodule VulnCommits.JudgeTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias VulnCommits.{Commit, Judge}
  alias VulnCommits.Judge.Store

  @model "gpt-test"
  @version "v1"

  setup do
    dir = Path.join(System.tmp_dir!(), "judge_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    %{path: Path.join(dir, "judgments.jsonl")}
  end

  defp commit(hash, opts \\ []) do
    %Commit{
      repo: Keyword.get(opts, :repo, "org/repo"),
      hash: hash,
      period: Keyword.get(opts, :period, :original),
      year: Keyword.get(opts, :year, 2014),
      keyword_hit: Keyword.get(opts, :keyword_hit, true),
      bot: Keyword.get(opts, :bot, false),
      message: "fix crash",
      files: ["lib/a.ex"],
      elixir_files: ["lib/a.ex"],
      date: ~D[2014-01-01]
    }
  end

  defp record(hash, run, label, opts \\ []) do
    %{
      hash: hash,
      repo: "org/repo",
      run: run,
      model: Keyword.get(opts, :model, @model),
      prompt_version: Keyword.get(opts, :version, @version),
      label: label,
      cia: nil,
      reason: nil,
      error: nil,
      usage: nil,
      judged_at: "2026-11-03T12:00:00Z"
    }
  end

  defp ok_judge(_commit, _dir, _run) do
    {:ok, %{label: :vulnerable, cia: "integrity", reason: "ok", usage: %{}}}
  end

  describe "candidates/3" do
    test "exclui bot e quem nao tem keyword_hit" do
      commits = [
        commit("a"),
        commit("b", bot: true),
        commit("c", keyword_hit: false)
      ]

      assert [%Commit{hash: "a"}] = Judge.candidates(commits, :original, years: nil)
    end

    test "filtra o periodo" do
      commits = [commit("a"), commit("b", period: :extended)]

      assert [%Commit{hash: "a"}] = Judge.candidates(commits, :original, years: nil)
    end

    test "respeita o intervalo de anos quando dado" do
      commits = [
        commit("a", year: 2011),
        commit("b", year: 2012),
        commit("c", year: 2016),
        commit("d", year: 2017)
      ]

      hashes = commits |> Judge.candidates(:original, years: 2012..2016) |> Enum.map(& &1.hash)
      assert hashes == ["b", "c"]
    end

    test "sem anos devolve todos os anos" do
      commits = [commit("a", year: 2011), commit("b", year: 2025)]

      assert length(Judge.candidates(commits, :original, years: nil)) == 2
    end
  end

  describe "pending/4" do
    test "devolve so os runs que faltam, por commit" do
      cands = [commit("a"), commit("b")]

      done =
        MapSet.new([
          {"a", 1, @model, @version},
          {"a", 2, @model, @version},
          {"b", 1, "outro-modelo", @version}
        ])

      pairs = Judge.pending(cands, done, @model, @version)

      assert Enum.map(pairs, fn {c, run} -> {c.hash, run} end) ==
               [{"a", 3}, {"b", 1}, {"b", 2}, {"b", 3}]
    end

    test "sem nada julgado sao 3 runs por candidato" do
      assert length(Judge.pending([commit("a")], MapSet.new(), @model, @version)) == 3
    end
  end

  describe "run/2" do
    test "grava 3 linhas por commit com o juiz falso", %{path: path} do
      pairs = Judge.pending([commit("a"), commit("b")], MapSet.new(), @model, @version)

      assert capture_io(fn ->
               assert :ok =
                        Judge.run(pairs,
                          dirs: %{"org/repo" => "/nao/usado"},
                          path: path,
                          model: @model,
                          version: @version,
                          judge_fun: &ok_judge/3
                        )
             end) =~ "julgados 6 de 6"

      records = Store.load(path)
      assert length(records) == 6
      assert Enum.all?(records, &(&1.label == "VULNERABLE"))
      assert Enum.all?(records, &(&1.model == @model and &1.prompt_version == @version))
      assert Enum.all?(records, &(&1.error == nil and &1.cia == "integrity"))
    end

    test "erro do juiz vira registro ERROR e a execucao termina", %{path: path} do
      pairs = Judge.pending([commit("a")], MapSet.new(), @model, @version)
      boom = fn _commit, _dir, _run -> {:error, :boom} end

      capture_io(fn ->
        assert :ok =
                 Judge.run(pairs,
                   dirs: %{"org/repo" => "/nao/usado"},
                   path: path,
                   model: @model,
                   version: @version,
                   judge_fun: boom
                 )
      end)

      records = Store.load(path)
      assert length(records) == 3
      assert Enum.all?(records, &(&1.label == "ERROR" and &1.error == ":boom"))
    end

    test "excecao do juiz vira ERROR e os outros pares continuam", %{path: path} do
      pairs = Judge.pending([commit("a"), commit("b")], MapSet.new(), @model, @version)

      raising = fn commit, _dir, _run ->
        if commit.hash == "a", do: raise("diff quebrado"), else: ok_judge(commit, nil, 1)
      end

      capture_io(fn ->
        assert :ok =
                 Judge.run(pairs,
                   dirs: %{"org/repo" => "/nao/usado"},
                   path: path,
                   model: @model,
                   version: @version,
                   judge_fun: raising
                 )
      end)

      records = Store.load(path)
      assert length(records) == 6

      errors = Enum.filter(records, &(&1.label == "ERROR"))
      assert [%{hash: "a", error: error}, _, _] = errors
      assert error == ~s({:exception, "diff quebrado"})
      assert Enum.count(records, &(&1.hash == "b" and &1.label == "VULNERABLE")) == 3
    end
  end

  describe "labels/4" do
    test "candidato com votos da maioria, nao candidato e candidato sem registro" do
      commits = [
        commit("a"),
        commit("b", bot: true),
        commit("c", keyword_hit: false),
        commit("d")
      ]

      records = [
        record("a", 1, "VULNERABLE"),
        record("a", 2, "VULNERABLE"),
        record("a", 3, "NEUTRAL")
      ]

      labels = Judge.labels(commits, records, @model, @version)

      assert labels["a"] == %{votes: [:vulnerable, :vulnerable, :neutral], final: :vulnerable}
      assert labels["b"] == %{votes: [], final: :neutral}
      assert labels["c"] == %{votes: [], final: :neutral}
      assert labels["d"] == %{votes: [], final: :undecided}
    end

    test "ignora registros de outro modelo ou versao de prompt" do
      commits = [commit("a")]

      records = [
        record("a", 1, "VULNERABLE", model: "outro"),
        record("a", 2, "VULNERABLE", version: "v2")
      ]

      assert Judge.labels(commits, records, @model, @version)["a"] == %{
               votes: [],
               final: :undecided
             }
    end
  end

  describe "unjudged/2" do
    test "conta candidatos com menos de 3 votos, sem contar nao candidatos" do
      commits = [
        commit("a"),
        commit("b"),
        commit("c"),
        commit("d", bot: true),
        commit("e", period: :extended)
      ]

      records = [
        record("a", 1, "VULNERABLE"),
        record("a", 2, "VULNERABLE"),
        record("a", 3, "NEUTRAL"),
        record("b", 1, "NEUTRAL"),
        record("b", 2, "VULNERABLE"),
        record("e", 1, "NEUTRAL")
      ]

      labels = Judge.labels(commits, records, @model, @version)

      candidates =
        Judge.candidates(commits, :original, years: nil) ++
          Judge.candidates(commits, :extended, years: nil)

      # b (2 votos), c (0 votos) e e (1 voto) ficam de fora dos finais
      assert Judge.unjudged(candidates, labels) == 3
    end
  end
end
