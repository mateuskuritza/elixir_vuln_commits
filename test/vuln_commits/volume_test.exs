defmodule VulnCommits.VolumeTest do
  use ExUnit.Case, async: true

  alias VulnCommits.{Commit, Volume}

  defp commit(hash, opts) do
    %Commit{
      repo: Keyword.get(opts, :repo, "r1"),
      hash: hash,
      year: Keyword.get(opts, :year, 2024),
      author_email: Keyword.get(opts, :email, "a@example.com"),
      elixir_files: Keyword.get(opts, :files, ["lib/a.ex"]),
      bot: Keyword.get(opts, :bot, false),
      period: :extended
    }
  end

  defp lines(pairs) do
    Map.new(pairs, fn {hash, added, deleted} -> {hash, %{added: added, deleted: deleted}} end)
  end

  test "collect soma só as linhas de arquivos Elixir" do
    numstat = fn "dir/r1", "a" ->
      [
        %{path: "lib/a.ex", added: 5, deleted: 2},
        %{path: "test/a_test.exs", added: 3, deleted: 0},
        %{path: "README.md", added: 40, deleted: 40}
      ]
    end

    rows = Volume.collect([commit("a", [])], %{"r1" => "dir/r1"}, numstat)

    assert rows == [%{repo: "r1", hash: "a", added: 8, deleted: 2}]
  end

  test "write e load guardam as linhas por hash" do
    path = Path.join(System.tmp_dir!(), "volume_#{System.unique_integer([:positive])}.csv")
    on_exit(fn -> File.rm(path) end)

    Volume.write([%{repo: "r1", hash: "a", added: 8, deleted: 2}], path)

    assert Volume.load(path) == %{"a" => %{added: 8, deleted: 2}}
  end

  test "per_year tem uma linha por ano de 2021 a 2025 e ignora bots" do
    commits = [
      commit("a", files: ["x.ex"], email: "a@example.com"),
      commit("b", files: ["x.ex", "y.ex", "z.ex"], email: "b@example.com"),
      commit("c", files: Enum.map(1..10, &"f#{&1}.ex"), email: "a@example.com"),
      commit("d", bot: true, files: ["x.ex"])
    ]

    volume = lines([{"a", 4, 1}, {"b", 10, 0}, {"c", 100, 50}, {"d", 999, 999}])
    rows = Volume.per_year(commits, volume)
    y2024 = Enum.find(rows, &(&1.year == 2024))

    assert Enum.map(rows, & &1.year) == Enum.to_list(2021..2025)

    assert y2024 == %{
             year: 2024,
             commits: 3,
             authors: 2,
             files: 14,
             files_per_commit: 4.67,
             large_pct: 33.33,
             median_added: 10.0,
             added: 114,
             deleted: 51
           }

    assert Enum.find(rows, &(&1.year == 2021)).commits == 0
    assert Enum.find(rows, &(&1.year == 2021)).files_per_commit == 0.0
  end

  test "per_repo separa por repositório e ano" do
    commits = [commit("a", repo: "r1", year: 2021), commit("b", repo: "r2", year: 2025)]
    rows = Volume.per_repo(commits, lines([{"a", 1, 0}, {"b", 7, 3}]))

    assert length(rows) == 10
    assert Enum.find(rows, &(&1.repo == "r2" and &1.year == 2025)).added == 7
    assert Enum.find(rows, &(&1.repo == "r2" and &1.year == 2021)).commits == 0
  end

  test "per_quarter agrupa pelo trimestre da data" do
    january = %{commit("a", []) | date: ~D[2024-01-15]}
    december = %{commit("b", []) | date: ~D[2024-12-31]}
    rows = Volume.per_quarter([december, january], lines([{"a", 1, 0}, {"b", 7, 3}]))

    assert Enum.map(rows, & &1.quarter) == ["2024T1", "2024T4"]
    assert Enum.map(rows, & &1.added) == [1, 7]
  end

  test "without_repo tira um repositório da conta" do
    commits = [commit("a", repo: "r1"), commit("b", repo: "r2")]
    rows = Volume.without_repo(commits, lines([{"a", 1, 0}, {"b", 7, 3}]), "r2")

    assert Enum.find(rows, &(&1.year == 2024)).added == 1
  end

  test "median com número par e ímpar de valores" do
    assert Volume.median([]) == 0.0
    assert Volume.median([3, 1, 2]) == 2.0
    assert Volume.median([4, 1, 2, 3]) == 2.5
  end
end
