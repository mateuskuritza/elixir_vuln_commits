defmodule VulnCommits.GitTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Git

  setup do
    fx = FixtureRepo.create!()
    on_exit(fn -> File.rm_rf(fx.dir) end)
    fx
  end

  defp range(opts \\ []) do
    Keyword.merge([since: ~D[2021-01-01], until: ~D[2025-12-31], no_merges: true], opts)
  end

  test "log sem merges devolve os commits de 2021 a 2025", fx do
    commits = Git.log(fx.dir, "main", range())
    by_hash = Map.new(commits, &{&1.hash, &1})

    assert length(commits) == 6
    assert Enum.sort(Map.keys(by_hash)) == Enum.sort([fx.b, fx.c, fx.d, fx.e, fx.f, fx.h])
    refute Map.has_key?(by_hash, fx.m)

    assert %{date: ~D[2021-03-02], message: "Fix crash on nil", merge?: false} = by_hash[fx.b]
    assert by_hash[fx.b].author_email == "fulano@example.com"
    assert by_hash[fx.b].author_name == "Fulano"
    assert by_hash[fx.c].author_name == "dependabot[bot]"
    assert by_hash[fx.d].date == ~D[2025-02-01]
    assert by_hash[fx.e].message == "Fix race in cache"
    assert by_hash[fx.f].date == ~D[2024-06-01]
    assert by_hash[fx.h].date == ~D[2025-05-01]
  end

  test "log com merges inclui M", fx do
    commits = Git.log(fx.dir, "main", range(no_merges: false))
    merge = Enum.find(commits, &(&1.hash == fx.m))

    assert length(commits) == 7
    assert merge.merge? == true
    assert merge.date == ~D[2025-04-01]
  end

  test "log filtra pela data do commit nas duas pontas", fx do
    commits = Git.log(fx.dir, "main", range(since: ~D[2025-03-01], until: ~D[2025-03-01]))

    assert Enum.map(commits, & &1.hash) == [fx.e]
  end

  test "files devolve os arquivos ordenados", fx do
    assert Git.files(fx.dir, fx.b) == ["README.md", "lib/a.ex"]
  end

  test "object_exists? acha o commit fora da main e nega hash inexistente", fx do
    assert Git.object_exists?(fx.dir, fx.g)
    refute Git.object_exists?(fx.dir, String.duplicate("0", 40))

    hashes = fx.dir |> Git.log("main", range(since: ~D[2018-01-01])) |> Enum.map(& &1.hash)
    refute fx.g in hashes
  end

  test "diff filtra pelos caminhos", fx do
    diff = Git.diff(fx.dir, fx.b, ["lib/a.ex"])

    assert diff =~ "+"
    assert diff =~ "lib/a.ex"
    refute diff =~ "README"
    assert Git.diff(fx.dir, fx.b, []) =~ "README"
  end

  test "first_added acha a data em que o arquivo entrou", fx do
    assert Git.first_added(fx.dir, "CLAUDE.md") == ~D[2025-02-01]
    assert Git.first_added(fx.dir, "nope.md") == nil
  end

  test "head e show_message", fx do
    assert Git.head(fx.dir, "main") == fx.h

    commit = Git.show_message(fx.dir, fx.e)
    assert %{hash: _, date: ~D[2025-03-01], message: "Fix race in cache"} = commit
    assert commit.hash == fx.e
  end

  test "default_branch de um clone", fx do
    clone = Path.join(System.tmp_dir!(), "vuln_clone_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(clone) end)
    {_, 0} = System.cmd("git", ["clone", "-q", fx.dir, clone], stderr_to_stdout: true)

    assert Git.default_branch(clone) == "main"
  end

  test "update traz commits novos e anda o HEAD do clone", fx do
    clone = Path.join(System.tmp_dir!(), "vuln_clone_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(clone) end)
    {_, 0} = System.cmd("git", ["clone", "-q", "--no-checkout", fx.dir, clone])

    {_, 0} = System.cmd("git", ["commit", "-q", "--allow-empty", "-m", "novo"], cd: fx.dir)
    {novo, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: fx.dir)

    assert Git.update(clone) == :ok
    assert Git.head(clone, "HEAD") == String.trim(novo)
  end

  test "clone_url monta a url do github" do
    assert Git.clone_url("owner/repo") == "https://github.com/owner/repo.git"
  end

  test "parse_log descarta byte inválido e detecta merge" do
    one =
      <<"h1", 0x1F, "2021-03-02T10:00:00+00:00", 0x1F, "a", 0x1F, "a@x", 0x1F, "p1", 0x1F, "msg ",
        0xFF, 0x1E>>

    assert [%{hash: "h1", message: "msg ", merge?: false, date: ~D[2021-03-02]}] =
             Git.parse_log(one)

    two = String.replace(one, "p1", "p1 p2")
    assert [%{merge?: true}] = Git.parse_log(two)
  end
end
