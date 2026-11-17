defmodule VulnCommits.ReposTest do
  use ExUnit.Case, async: true

  alias VulnCommits.{Commit, Repos}

  describe "active?/2" do
    test "as quatro combinações da regra" do
      refute Repos.active?([], [])
      refute Repos.active?([:x], [])
      assert Repos.active?([:x, :y], [])
      assert Repos.active?([], [:x])
    end
  end

  describe "resolve_all/2" do
    setup do
      fx = FixtureRepo.create!()
      on_exit(fn -> File.rm_rf(fx.dir) end)

      dataset = [
        %Commit{repo: "fixture", hash: fx.a},
        %Commit{repo: "fixture", hash: fx.g}
      ]

      base = [
        repo_map: %{"fixture" => "x/fixture"},
        clone_fun: fn _owner_repo, _dir -> fx.dir end,
        info_fun: fn _ -> {:ok, %{stars: 1, archived: false, default_branch: "main"}} end,
        today: ~D[2026-10-21]
      ]

      %{fx: fx, dataset: dataset, base: base}
    end

    test "resolve o repositório e conta a atividade", %{fx: fx, dataset: dataset, base: base} do
      assert [row] = Repos.resolve_all(dataset, base)

      assert row.name == "fixture"
      assert row.owner_repo == "x/fixture"
      assert row.dir == fx.dir
      assert row.stars == 1
      assert row.archived == false
      assert row.default_branch == "main"
      assert row.head_at_collection == fx.h
      assert row.hashes_expected == 2
      assert row.hashes_found == 2
      assert row.elixir_commits_2025 == 2
      assert row.elixir_commits_2026 == 0
      assert row.last_elixir_commit == ~D[2025-05-01]
      assert row.active == true
      assert row.collected_at == ~D[2026-10-21]
    end

    test "repositório arquivado nunca é ativo", %{dataset: dataset, base: base} do
      info = fn _ -> {:ok, %{stars: 1, archived: true, default_branch: "main"}} end
      assert [row] = Repos.resolve_all(dataset, Keyword.put(base, :info_fun, info))
      assert row.archived == true
      assert row.active == false
    end

    test "hash faltando não aborta, só aparece na contagem", %{dataset: dataset, base: base} do
      missing = %Commit{repo: "fixture", hash: String.duplicate("0", 40)}

      output =
        ExUnit.CaptureIO.capture_io(:stderr, fn ->
          assert [row] = Repos.resolve_all([missing | dataset], base)
          assert row.hashes_expected == 3
          assert row.hashes_found == 2
        end)

      assert output =~ String.duplicate("0", 40)
    end
  end

  describe "write/load" do
    test "ida e volta preserva os tipos" do
      path = Path.join(System.tmp_dir!(), "repos_#{System.unique_integer([:positive])}.csv")
      on_exit(fn -> File.rm(path) end)

      rows = [
        %{
          name: "a",
          owner_repo: "x/a",
          dir: "repos/a",
          stars: 10,
          archived: false,
          default_branch: "main",
          head_at_collection: String.duplicate("a", 40),
          hashes_expected: 3,
          hashes_found: 3,
          elixir_commits_2025: 2,
          elixir_commits_2026: 0,
          last_elixir_commit: ~D[2025-05-01],
          active: true,
          collected_at: ~D[2026-10-21]
        },
        %{
          name: "b",
          owner_repo: "x/b",
          dir: "repos/b",
          stars: 0,
          archived: true,
          default_branch: "master",
          head_at_collection: String.duplicate("b", 40),
          hashes_expected: 1,
          hashes_found: 1,
          elixir_commits_2025: 0,
          elixir_commits_2026: 0,
          last_elixir_commit: nil,
          active: false,
          collected_at: ~D[2026-10-21]
        }
      ]

      Repos.write(path, rows)
      assert Repos.load(path) == rows
      assert Repos.active(rows) == [hd(rows)]
    end
  end
end
