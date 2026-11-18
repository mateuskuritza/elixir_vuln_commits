defmodule VulnCommits.VolumeTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Volume

  defp row(hash, opts) do
    year = Keyword.get(opts, :year, 2024)

    %{
      repo: Keyword.get(opts, :repo, "r1"),
      hash: hash,
      date: Keyword.get(opts, :date, Date.new!(year, 6, 1)),
      year: year,
      author_email: Keyword.get(opts, :email, "a@example.com"),
      bot: Keyword.get(opts, :bot, false),
      files: Keyword.get(opts, :files, 1),
      added: Keyword.get(opts, :added, 0),
      deleted: Keyword.get(opts, :deleted, 0)
    }
  end

  describe "collect/2 no repositório de teste" do
    setup do
      fx = FixtureRepo.create!()
      on_exit(fn -> File.rm_rf(fx.dir) end)
      fx
    end

    test "mede os commits com arquivo Elixir, sem merges", fx do
      repo = %{name: "fixture", dir: fx.dir, default_branch: "main"}
      rows = Volume.collect([repo], since: ~D[2020-01-01], until: ~D[2025-12-31])
      by_hash = Map.new(rows, &{&1.hash, &1})

      assert Enum.sort(Map.keys(by_hash)) == Enum.sort([fx.a, fx.b, fx.e, fx.f, fx.h])

      assert by_hash[fx.b] == %{
               repo: "fixture",
               hash: fx.b,
               date: ~D[2021-03-02],
               year: 2021,
               author_email: "fulano@example.com",
               bot: false,
               files: 1,
               added: 1,
               deleted: 0
             }
    end
  end

  test "lines_of soma só as linhas de arquivos Elixir" do
    numstat = [
      %{path: "lib/a.ex", added: 5, deleted: 2},
      %{path: "test/a_test.exs", added: 3, deleted: 0},
      %{path: "README.md", added: 40, deleted: 40}
    ]

    assert Volume.lines_of(numstat) == %{files: 2, added: 8, deleted: 2}
  end

  test "write e load guardam uma linha por commit" do
    path = Path.join(System.tmp_dir!(), "volume_#{System.unique_integer([:positive])}.csv")
    on_exit(fn -> File.rm(path) end)
    rows = [row("a", added: 8, deleted: 2, files: 3, date: ~D[2024-02-03])]

    Volume.write(rows, path)

    assert Volume.load(path) == rows
    assert Volume.by_hash(rows)["a"].added == 8
  end

  test "per_year tem uma linha por ano pedido e ignora bots" do
    rows = [
      row("a", files: 1, added: 4, deleted: 1, email: "a@example.com"),
      row("b", files: 3, added: 10, email: "b@example.com", repo: "r2"),
      row("c", files: 10, added: 100, deleted: 50, email: "a@example.com"),
      row("d", bot: true, files: 1, added: 999, deleted: 999)
    ]

    result = Volume.per_year(rows, [2023, 2024])

    assert Enum.map(result, & &1.year) == [2023, 2024]

    assert Enum.find(result, &(&1.year == 2024)) == %{
             year: 2024,
             commits: 3,
             repos: 2,
             authors: 2,
             files: 14,
             files_per_commit: 4.67,
             large_pct: 33.33,
             median_added: 10.0,
             added: 114,
             deleted: 51,
             commits_per_author: 1.5,
             files_per_author: 7.0,
             added_per_author: 57.0
           }

    assert Enum.find(result, &(&1.year == 2023)).commits == 0
    assert Enum.find(result, &(&1.year == 2023)).files_per_commit == 0.0
  end

  test "frequent_authors conta só quem tem dez commits ou mais no ano" do
    frequent = Enum.map(1..10, &row("f#{&1}", email: "f@example.com", files: 2, added: 30))
    occasional = [row("o1", email: "o@example.com", added: 500)]
    bot = Enum.map(1..10, &row("b#{&1}", email: "bot@example.com", bot: true))

    result = Volume.frequent_authors(frequent ++ occasional ++ bot, [2023, 2024])

    assert Enum.find(result, &(&1.year == 2024)) == %{
             year: 2024,
             authors: 1,
             single_commit_pct: 50.0,
             commits_pct: 90.91,
             commits_per_author: 10.0,
             files_per_author: 20.0,
             added_per_author: 300.0
           }

    assert Enum.find(result, &(&1.year == 2023)).authors == 0
    assert Enum.find(result, &(&1.year == 2023)).added_per_author == 0.0
  end

  test "per_repo separa por repositório e ano" do
    rows = [
      row("a", repo: "r1", year: 2021, added: 1),
      row("b", repo: "r2", year: 2025, added: 7)
    ]

    result = Volume.per_repo(rows, Enum.to_list(2021..2025))

    assert length(result) == 10
    assert Enum.find(result, &(&1.repo == "r2" and &1.year == 2025)).added == 7
    assert Enum.find(result, &(&1.repo == "r2" and &1.year == 2021)).commits == 0
  end

  test "per_quarter agrupa pelo trimestre da data" do
    rows = [
      row("b", date: ~D[2024-12-31], added: 7),
      row("a", date: ~D[2024-01-15], added: 1)
    ]

    result = Volume.per_quarter(rows)

    assert Enum.map(result, & &1.quarter) == ["2024T1", "2024T4"]
    assert Enum.map(result, & &1.added) == [1, 7]
  end

  test "without_repo tira um repositório da conta" do
    rows = [row("a", repo: "r1", added: 1), row("b", repo: "r2", added: 7)]
    result = Volume.without_repo(rows, "r2", [2024])

    assert hd(result).added == 1
  end

  test "median com número par e ímpar de valores" do
    assert Volume.median([]) == 0.0
    assert Volume.median([3, 1, 2]) == 2.0
    assert Volume.median([4, 1, 2, 3]) == 2.5
  end
end
