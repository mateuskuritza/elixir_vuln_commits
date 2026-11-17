defmodule VulnCommits.CollectTest do
  use ExUnit.Case, async: true

  alias VulnCommits.{Collect, Commit}

  describe "enrich/1" do
    test "preenche palavras-chave, bot e ano" do
      commit =
        Collect.enrich(%Commit{
          message: "Fix crash",
          author_name: "dependabot[bot]",
          date: ~D[2022-01-10]
        })

      assert commit.keyword_hit == true
      assert commit.keywords == ["crash"]
      assert commit.bot == true
      assert commit.year == 2022
    end

    test "marcadores de ia vêm da mensagem" do
      commit =
        Collect.enrich(%Commit{
          message: "add thing\n\nCo-Authored-By: Claude <x@y.z>",
          author_name: "Fulano",
          date: ~D[2025-01-01]
        })

      assert commit.ai_markers == ["claude"]
      assert commit.bot == false
      assert commit.keyword_hit == false
    end
  end

  describe "extended/2 e original/2" do
    setup do
      fx = FixtureRepo.create!()
      on_exit(fn -> File.rm_rf(fx.dir) end)
      row = %{name: "fixture", dir: fx.dir, default_branch: "main", active: true}
      %{fx: fx, row: row}
    end

    test "extended devolve só commits não-merge que tocam arquivo elixir", %{fx: fx, row: row} do
      commits = Collect.extended([row], since: ~D[2021-01-01], until: ~D[2025-12-31])

      assert commits |> Enum.map(& &1.hash) |> Enum.sort() == Enum.sort([fx.b, fx.e, fx.f, fx.h])

      b = Enum.find(commits, &(&1.hash == fx.b))
      f = Enum.find(commits, &(&1.hash == fx.f))
      assert b.keyword_hit == true
      assert f.keyword_hit == false
      assert b.period == :extended
      assert b.human_label == nil
      assert b.repo == "fixture"
      assert b.year == 2021
      assert b.files == ["README.md", "lib/a.ex"]
      assert b.elixir_files == ["lib/a.ex"]
      assert b.merge? == false
      assert Enum.all?(commits, &(&1.period == :extended))
    end

    test "merges_excluded conta os merges fora do índice", %{row: row} do
      assert Collect.merges_excluded(row, since: ~D[2021-01-01], until: ~D[2025-12-31]) == 1
    end

    test "original mantém files e rótulo do csv e usa a mensagem do git", %{fx: fx, row: row} do
      dataset = [
        %Commit{
          repo: "fixture",
          hash: fx.b,
          date: ~D[2021-03-02],
          year: 2021,
          message: "texto do csv",
          files: ["lib/a.ex"],
          elixir_files: ["lib/a.ex"],
          human_label: :vulnerable,
          period: :original
        },
        %Commit{
          repo: "fixture",
          hash: String.duplicate("0", 40),
          date: ~D[2020-01-01],
          year: 2020,
          message: "Fix crash Co-Authored-By: Claude",
          files: ["x.ex"],
          elixir_files: ["x.ex"],
          human_label: :neutral,
          period: :original
        },
        %Commit{repo: "outro", hash: fx.a, date: ~D[2020-05-01], message: "x", period: :original}
      ]

      assert [b, ghost] = Collect.original(dataset, [row])

      assert b.message == "Fix crash on nil"
      assert b.author_name == "Fulano"
      assert b.author_email == "fulano@example.com"
      assert b.files == ["lib/a.ex"]
      assert b.elixir_files == ["lib/a.ex"]
      assert b.human_label == :vulnerable
      assert b.period == :original
      assert b.keyword_hit == true
      assert b.year == 2021

      assert ghost.message == "Fix crash Co-Authored-By: Claude"
      assert ghost.author_name == nil
      assert ghost.bot == false
      assert ghost.ai_markers == ["claude"]
      assert ghost.keyword_hit == true
    end

    test "repo_markers acha só arquivos que existem no histórico", %{fx: fx, row: row} do
      assert Collect.repo_markers([row]) == [
               %{repo: "fixture", file: "CLAUDE.md", first_added: ~D[2025-02-01]}
             ]

      assert fx.d
    end
  end

  describe "write/2 e load/1" do
    @tag :tmp_dir
    test "ida e volta preserva os campos, mesmo com mensagem difícil", %{tmp_dir: tmp} do
      path = Path.join(tmp, "commits.csv")

      tricky = "Fix crash, \"quoted\" part\n\nsegunda linha, com vírgula\nterceira"

      commits = [
        %Commit{
          period: :original,
          repo: "r",
          hash: "abc",
          date: ~D[2019-04-05],
          year: 2019,
          author_name: "Fulano, Jr.",
          author_email: "f@x.y",
          merge?: false,
          keyword_hit: true,
          keywords: ["crash", "denial service"],
          bot: false,
          ai_markers: ["claude", "cursor"],
          human_label: :vulnerable,
          files: ["a.ex", "b/c.exs"],
          elixir_files: ["a.ex", "b/c.exs"],
          message: tricky
        },
        %Commit{
          period: :extended,
          repo: "s",
          hash: "def",
          date: ~D[2024-12-31],
          year: 2024,
          author_name: nil,
          author_email: nil,
          merge?: true,
          keyword_hit: false,
          keywords: [],
          bot: true,
          ai_markers: [],
          human_label: nil,
          files: [],
          elixir_files: [],
          message: ""
        }
      ]

      Collect.write(commits, path)
      assert Collect.load(path) == commits
    end
  end
end
