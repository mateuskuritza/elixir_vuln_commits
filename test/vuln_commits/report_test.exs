defmodule VulnCommits.ReportTest do
  use ExUnit.Case, async: true

  alias VulnCommits.{Commit, Report}

  defp commit(hash, opts) do
    year = Keyword.get(opts, :year, 2018)

    %Commit{
      repo: Keyword.get(opts, :repo, "alfa"),
      hash: hash,
      year: year,
      date: Date.new!(year, 6, 1),
      elixir_files: Keyword.get(opts, :files, ["lib/a.ex"]),
      human_label: Keyword.get(opts, :human, :neutral),
      period: Keyword.get(opts, :period, :original),
      keyword_hit: Keyword.get(opts, :hit, false),
      bot: Keyword.get(opts, :bot, false),
      ai_markers: Keyword.get(opts, :ai, [])
    }
  end

  defp labels_from(commits) do
    Map.new(commits, fn c -> {c.hash, %{votes: [], final: c.human_label || :neutral}} end)
  end

  defp three do
    [
      commit("a", human: :neutral),
      commit("b", human: :neutral, repo: "beta", files: ["lib/b.ex"]),
      commit("c", human: :vulnerable, files: ["lib/a.ex", "lib/c.ex"])
    ]
  end

  describe "constantes do artigo" do
    test "tabela 3 e totais" do
      assert Report.paper_table3()[2019] == 3.45
      assert Report.paper_totals().commits == 4446
      assert Report.paper_totals().repos == 25
      assert Report.paper_totals().files == 1769
    end
  end

  describe "match/2" do
    test "rótulos concordando dão human_active igual a ours e paper fixo" do
      commits = three()
      rows = Report.match(commits, labels_from(commits))

      assert Enum.all?(rows, &(&1.human_active == &1.ours))

      by_metric = Map.new(rows, &{&1.metric, &1})
      assert by_metric["commits"].paper == 4446
      assert by_metric["commits"].ours == 3
      assert by_metric["vulneráveis"].ours == 1
      assert by_metric["vulneráveis"].paper == 90
      assert by_metric["proporção (%)"].ours == 33.33
      assert by_metric["repositórios"].ours == 2
      assert by_metric["repositórios"].paper == 25
      assert by_metric["repositórios com ≥1 vulnerável"].ours == 1
      assert by_metric["arquivos"].ours == 3
      assert by_metric["arquivos em vulneráveis"].ours == 2
      assert by_metric["arquivos em vulneráveis (%)"].ours == 66.67
      assert by_metric["arquivos em vulneráveis (%)"].paper == 18.03
    end

    test "ordem das linhas" do
      metrics = Enum.map(Report.match(three(), labels_from(three())), & &1.metric)

      assert metrics == [
               "commits",
               "vulneráveis",
               "proporção (%)",
               "repositórios",
               "repositórios com ≥1 vulnerável",
               "arquivos",
               "arquivos em vulneráveis",
               "arquivos em vulneráveis (%)"
             ]
    end

    test "undecided conta como neutral" do
      commits = three()
      labels = Map.put(labels_from(commits), "c", %{votes: [], final: :undecided})
      by_metric = Map.new(Report.match(commits, labels), &{&1.metric, &1})
      assert by_metric["vulneráveis"].ours == 0
      assert by_metric["vulneráveis"].human_active == 1
    end
  end

  describe "files_pct/2" do
    test "arquivos distintos em vulneráveis sobre arquivos distintos de todos" do
      commits = [
        commit("a", human: :vulnerable, files: ["x.ex", "y.ex"]),
        commit("b", human: :neutral, files: ["y.ex", "z.ex", "w.ex"])
      ]

      assert Report.files_pct(commits, labels_from(commits)) == 50.0
    end

    test "mesmo caminho em repos diferentes conta separado" do
      commits = [
        commit("a", human: :vulnerable, repo: "r1", files: ["x.ex"]),
        commit("b", human: :neutral, repo: "r2", files: ["x.ex"])
      ]

      assert Report.files_pct(commits, labels_from(commits)) == 50.0
    end

    test "sem commits devolve zero" do
      assert Report.files_pct([], %{}) == 0.0
    end
  end

  describe "volume e vulnerabilidade" do
    test "vulnerable_density divide os vulneráveis pelas linhas adicionadas" do
      extended = [
        commit("e1", year: 2024, period: :extended, human: :vulnerable),
        commit("e2", year: 2024, period: :extended),
        commit("e3", year: 2024, period: :extended, human: :vulnerable, bot: true)
      ]

      lines = %{
        "e1" => %{added: 1500, deleted: 0},
        "e2" => %{added: 500, deleted: 0},
        "e3" => %{added: 9000, deleted: 0}
      }

      rows = Report.vulnerable_density(extended, labels_from(extended), lines)

      assert Enum.find(rows, &(&1.year == 2024)) ==
               %{name: "2024", year: 2024, vulnerable: 1, added: 2000, per_10k_lines: 5.0}

      assert Enum.find(rows, &(&1.year == 2021)).per_10k_lines == 0.0
    end

    test "vulnerable_density_periods junta os anos de cada período" do
      commits = [
        commit("o1", year: 2015, period: :original, human: :vulnerable),
        commit("o2", year: 2019, period: :original),
        commit("e1", year: 2024, period: :extended, human: :vulnerable),
        commit("e2", year: 2025, period: :extended, human: :vulnerable)
      ]

      lines = %{
        "o1" => %{added: 1000, deleted: 0},
        "o2" => %{added: 1000, deleted: 0},
        "e1" => %{added: 5000, deleted: 0},
        "e2" => %{added: 5000, deleted: 0}
      }

      rows =
        Report.vulnerable_density_periods(commits, labels_from(commits), lines, [
          2012..2020,
          2021..2025
        ])

      assert rows == [
               %{name: "2012 a 2020", vulnerable: 1, added: 2000, per_10k_lines: 5.0},
               %{name: "2021 a 2025", vulnerable: 2, added: 10000, per_10k_lines: 2.0}
             ]
    end

    test "vulnerable_by_size separa os commits por número de arquivos" do
      many = Enum.map(1..12, &"lib/f#{&1}.ex")

      extended = [
        commit("e1", period: :extended, human: :vulnerable),
        commit("e2", period: :extended),
        commit("e3", period: :extended, files: ["a.ex", "b.ex"]),
        commit("e4", period: :extended, files: many, human: :vulnerable)
      ]

      rows = Report.vulnerable_by_size(extended, labels_from(extended))

      assert rows == [
               %{band: "1", commits: 2, vulnerable: 1, proportion: 50.0},
               %{band: "2 a 4", commits: 1, vulnerable: 0, proportion: 0.0},
               %{band: "5 a 9", commits: 0, vulnerable: 0, proportion: 0.0},
               %{band: "10 ou mais", commits: 1, vulnerable: 1, proportion: 100.0}
             ]
    end
  end

  describe "per_year/3" do
    test "14 linhas de 2012 a 2025" do
      original = three()
      extended = [commit("e1", year: 2022, period: :extended)]
      rows = Report.per_year(original, extended, labels_from(original ++ extended))

      assert Enum.map(rows, & &1.year) == Enum.to_list(2012..2025)
      assert length(rows) == 14
    end

    test "originais têm paper e humano, estendido não" do
      original = three()
      rows = Report.per_year(original, [], labels_from(original))
      y2018 = Enum.find(rows, &(&1.year == 2018))
      assert y2018.commits == 3
      assert y2018.paper == 1.05
      assert y2018.human_active == 33.33
      assert y2018.ours == 33.33

      y2013 = Enum.find(rows, &(&1.year == 2013))
      assert y2013.commits == 0
      assert y2013.ours == 0.0
    end

    test "estendido exclui bots e usa só o rótulo do modelo" do
      extended = [
        commit("e1", year: 2022, period: :extended, hit: true),
        commit("e2", year: 2022, period: :extended, hit: true),
        commit("e3", year: 2022, period: :extended, bot: true)
      ]

      labels = %{
        "e1" => %{votes: [:vulnerable, :vulnerable, :neutral], final: :vulnerable},
        "e2" => %{votes: [], final: :undecided},
        "e3" => %{votes: [], final: :neutral}
      }

      y2022 = Enum.find(Report.per_year([], extended, labels), &(&1.year == 2022))
      assert y2022.commits == 2
      assert y2022.paper == nil
      assert y2022.human_active == nil
      assert y2022.ours == 50.0
    end
  end

  describe "agreement/4" do
    test "rótulos perfeitos dão kappa 1 no eval" do
      original = [
        commit("a", year: 2018, human: :vulnerable),
        commit("b", year: 2019, human: :neutral),
        commit("c", year: 2014, human: :neutral)
      ]

      result = Report.agreement(original, labels_from(original), [])
      assert result.eval.kappa == 1.0
      assert result.eval.n == 2
      assert result.dev.n == 1
      assert result.all.n == 3
      assert result.eval.confusion.true_pos == 1
      assert result.eval.precision == 1.0
      assert result.eval.recall == 1.0
      assert result.eval.f1 == 1.0
    end

    test "undecided entra como neutral na matriz" do
      original = [commit("a", year: 2018, human: :vulnerable)]
      labels = %{"a" => %{votes: [], final: :undecided}}
      result = Report.agreement(original, labels, [])
      assert result.eval.confusion.false_neg == 1
      assert result.runs.undecided == 1
    end

    test "sem julgamentos os campos de runs são nil" do
      original = three()
      runs = Report.agreement(original, labels_from(original), []).runs
      assert runs.mean_kappa == nil
      assert runs.min_kappa == nil
      assert runs.unanimous_pct == nil
      assert runs.undecided == 0
    end

    test "runs com 3 votos calculam kappa entre execuções e unanimidade" do
      original = [commit("a", hit: true), commit("b", hit: true)]
      extended = [commit("c", hit: true, period: :extended, year: 2022)]

      labels = %{
        "a" => %{votes: [:vulnerable, :vulnerable, :vulnerable], final: :vulnerable},
        "b" => %{votes: [:neutral, :neutral, :neutral], final: :neutral},
        "c" => %{votes: [:vulnerable, :neutral, :neutral], final: :neutral}
      }

      runs = Report.agreement(original, labels, extended).runs
      assert runs.n == 3
      assert runs.unanimous_pct == 66.67
      assert runs.min_kappa < 1.0
      assert runs.mean_kappa < 1.0
      assert runs.undecided == 0
    end
  end

  describe "bots/1" do
    test "conta bots e total por ano de 2021 a 2025" do
      extended = [
        commit("a", year: 2021, bot: true, period: :extended),
        commit("b", year: 2021, period: :extended),
        commit("c", year: 2023, period: :extended)
      ]

      rows = Report.bots(extended)
      assert Enum.map(rows, & &1.year) == Enum.to_list(2021..2025)
      assert Enum.find(rows, &(&1.year == 2021)) == %{year: 2021, bots: 1, total: 2}
      assert Enum.find(rows, &(&1.year == 2024)) == %{year: 2024, bots: 0, total: 0}
    end
  end

  describe "ai/3" do
    test "separa commits com e sem marcador e conta vulneráveis de cada lado" do
      extended = [
        commit("a", year: 2024, period: :extended, ai: ["claude"]),
        commit("b", year: 2024, period: :extended, ai: ["copilot"]),
        commit("c", year: 2024, period: :extended),
        commit("d", year: 2024, period: :extended),
        commit("e", year: 2024, period: :extended, bot: true)
      ]

      labels = %{
        "a" => %{votes: [], final: :vulnerable},
        "b" => %{votes: [], final: :neutral},
        "c" => %{votes: [], final: :vulnerable},
        "d" => %{votes: [], final: :undecided},
        "e" => %{votes: [], final: :neutral}
      }

      markers = [%{repo: "alfa", file: "CLAUDE.md", first_added: ~D[2025-02-03]}]
      result = Report.ai(extended, labels, markers)

      y = Enum.find(result.per_year, &(&1.year == 2024))

      assert y == %{
               year: 2024,
               with_marker: 2,
               vulnerable_with: 1,
               without_marker: 2,
               vulnerable_without: 1
             }

      assert length(result.per_year) == 5
      assert result.repo_files == markers
    end
  end
end
