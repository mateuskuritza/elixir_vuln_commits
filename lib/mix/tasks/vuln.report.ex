defmodule Mix.Tasks.Vuln.Report do
  use Mix.Task

  alias VulnCommits.{Collect, CSV, Judge, Latex, Metrics, Population, Report, Sample, Volume}
  alias VulnCommits.Judge.{Batch, Prompt, Store}

  @shortdoc "Gera as tabelas do relatório em out/ (use --dev para só a concordância de 2012-2016)"

  @commits "data/commits.csv"
  @markers "data/repo_markers.csv"
  @judgments "data/judgments.jsonl"
  @labeled "data/sample_80_labeled.csv"
  @volume "data/volume.csv"
  @volume_original "data/volume_original.csv"
  @complement "data/commits_complement.csv"
  @out "out"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [dev: :boolean])

    commits = Collect.load(@commits)
    original = Enum.filter(commits, fn commit -> commit.period == :original end)
    extended = Enum.filter(commits, fn commit -> commit.period == :extended end)

    records = Store.load(@judgments)
    labels = Judge.labels(commits, records, Batch.model(), Prompt.version())
    warn_if_empty(labels)

    original_candidates = Judge.candidates(commits, :original, years: nil)
    extended_candidates = Judge.candidates(commits, :extended, years: nil)
    candidates = original_candidates ++ extended_candidates

    warn_unjudged(candidates, labels)

    agreement = Report.agreement(original, labels, extended)

    if opts[:dev] do
      print_dev(agreement.dev)
    else
      markers = load_markers()

      summary = %{
        model: Batch.model(),
        prompt_version: Prompt.version(),
        match: Report.match(original, labels),
        per_year: Report.per_year(original, extended, labels),
        agreement: agreement,
        manual: manual_agreement(labels),
        bots: Report.bots(extended),
        ai: Report.ai(extended, labels, markers),
        volume: volume(original, extended, labels)
      }

      write_all(summary)
      write_population(original, extended, records)
    end
  end

  # histórico completo de 2012 a 2020: dataset + commits de fora (mix vuln.complement)
  defp write_population(original, extended, records) do
    if File.exists?(@complement) do
      complement = Collect.load(@complement)
      all = original ++ extended ++ complement
      labels = Judge.labels(all, records, Batch.model(), Prompt.version())
      full = original ++ complement
      recent = Enum.reject(extended, fn commit -> commit.bot end)
      early = Enum.filter(recent, fn commit -> commit.year <= 2023 end)
      late = Enum.filter(recent, fn commit -> commit.year >= 2024 end)

      without = fn commits, repos ->
        Enum.reject(commits, fn commit -> commit.repo in repos end)
      end

      periods = [
        Population.row("2012-2020, dataset original", original, labels),
        Population.row("2012-2020, fora do dataset", complement, labels),
        Population.row("2012-2020, histórico completo", full, labels),
        Population.row("2021-2023", early, labels),
        Population.row("2024-2025", late, labels),
        Population.row("2021-2025", recent, labels)
      ]

      comparisons =
        Enum.flat_map([[], ["elixir"], ["analytics"], ["analytics", "realtime"]], fn repos ->
          suffix = if repos == [], do: "", else: " sem " <> Enum.join(repos, "+")
          base = without.(full, repos)

          [
            Population.compare(
              "2012-2020 x 2021-2025" <> suffix,
              base,
              without.(recent, repos),
              labels
            ),
            Population.compare(
              "2012-2020 x 2021-2023" <> suffix,
              base,
              without.(early, repos),
              labels
            ),
            Population.compare(
              "2012-2020 x 2024-2025" <> suffix,
              base,
              without.(late, repos),
              labels
            )
          ]
        end) ++ [Population.compare("2021-2023 x 2024-2025", early, late, labels)]

      lines = Volume.by_hash(Volume.load(@volume))

      per_year =
        Enum.map(2012..2025, fn year ->
          group = Enum.filter(full ++ recent, fn commit -> commit.year == year end)
          vulnerable = Population.count(group, labels)

          on_branch =
            Enum.filter(Map.values(lines), fn row -> row.year == year and not row.bot end)

          added = Enum.sum(Enum.map(on_branch, fn row -> row.added end))

          [
            year,
            length(group),
            vulnerable,
            Metrics.proportion(vulnerable, length(group)),
            added,
            Float.round(1.0e4 * vulnerable / max(added, 1), 2)
          ]
        end)

      length_rows =
        Enum.zip(Population.by_length(full, labels), Population.by_length(recent, labels))
        |> Enum.map(fn {a, b} ->
          [
            bin_name(a.bin),
            a.commits,
            a.candidates,
            a.vulnerable,
            b.commits,
            b.candidates,
            b.vulnerable
          ]
        end)

      standardized = [
        [
          "2021-2025",
          Population.row("", recent, labels).pct,
          Population.standardized(recent, full, labels)
        ],
        [
          "2021-2023",
          Population.row("", early, labels).pct,
          Population.standardized(early, full, labels)
        ],
        [
          "2024-2025",
          Population.row("", late, labels).pct,
          Population.standardized(late, full, labels)
        ]
      ]

      [
        {"periodos", ["recorte", "commits", "vulneráveis", "%"],
         Enum.map(periods, fn row -> [row.name, row.commits, row.vulnerable, row.pct] end),
         "Proporção de vulneráveis por recorte (classificador)"},
        {"comparacoes",
         [
           "comparação",
           "vuln. A",
           "commits A",
           "% A",
           "vuln. B",
           "commits B",
           "% B",
           "p (Fisher)"
         ],
         Enum.map(comparisons, fn c ->
           [
             c.name,
             c.left.vulnerable,
             c.left.commits,
             c.left.pct,
             c.right.vulnerable,
             c.right.commits,
             c.right.pct,
             Float.round(c.p, 4)
           ]
         end), "Comparação entre períodos com a mesma população"},
        {"per_year_full",
         ["ano", "commits", "vulneráveis", "%", "linhas adicionadas", "por 10 mil linhas"],
         per_year, "Histórico completo por ano"},
        {"mensagem",
         [
           "palavras",
           "commits 2012-2020",
           "cand. (%)",
           "vuln. (%)",
           "commits 2021-2025",
           "cand. (%)",
           "vuln. (%)"
         ], length_rows, "Taxas por tamanho da mensagem"},
        {"mensagem_padronizada", ["período", "bruto (%)", "padronizado (%)"], standardized,
         "Proporção reponderada pela distribuição de tamanho de mensagem de 2012-2020"}
      ]
      |> Enum.each(fn table -> write_table(table) end)

      Mix.shell().info("tabelas do histórico completo gravadas em #{@out}/")
    end
  end

  defp bin_name({low, :inf}), do: "#{low}+"
  defp bin_name({low, high}), do: "#{low}-#{high}"

  defp warn_if_empty(labels) do
    no_votes =
      Enum.all?(labels, fn {_hash, label} ->
        label.votes == []
      end)

    if no_votes do
      Mix.shell().info(
        "AVISO: sem julgamentos ainda (#{@judgments}). todo candidato conta como neutral."
      )
    end
  end

  defp warn_unjudged(candidates, labels) do
    count = Judge.unjudged(candidates, labels)

    if count > 0 do
      Mix.shell().info(
        "AVISO: #{count} candidatos com menos de 3 votos válidos; os números de 'nosso' ainda não são finais"
      )
    end
  end

  defp print_dev(dev) do
    Mix.shell().info("dev (2012-2016): n=#{dev.n}")
    Mix.shell().info("kappa: #{Float.round(dev.kappa, 4)}")
    Mix.shell().info("precisao: #{Float.round(dev.precision, 4)}")
    Mix.shell().info("revocacao: #{Float.round(dev.recall, 4)}")
    Mix.shell().info("f1: #{Float.round(dev.f1, 4)}")
    Mix.shell().info("confusao: #{inspect(dev.confusion)}")
  end

  defp load_markers() do
    if File.exists?(@markers) do
      rows = CSV.read(@markers)

      Enum.map(rows, fn row ->
        %{
          repo: row["repo"],
          file: row["file"],
          first_added: Date.from_iso8601!(row["first_added"])
        }
      end)
    else
      []
    end
  end

  defp volume(original, extended, labels) do
    if File.exists?(@volume) do
      rows = Volume.load(@volume)
      years = Enum.to_list(2012..2025)

      # com volume_original.csv a densidade cobre também 2012 a 2020 (só os commits do dataset)
      {density_commits, lines, density_years} =
        if File.exists?(@volume_original) do
          lines = Volume.by_hash(rows ++ Volume.load(@volume_original))
          {original ++ extended, lines, 2012..2025}
        else
          {extended, Volume.by_hash(rows), 2021..2025}
        end

      %{
        per_year: Volume.per_year(rows, years),
        per_repo: Volume.per_repo(rows, years),
        per_quarter: Volume.per_quarter(rows),
        frequent_authors: Volume.frequent_authors(rows, years),
        without_analytics: Volume.without_repo(rows, "analytics", years),
        vulnerable_density:
          Report.vulnerable_density(density_commits, labels, lines, density_years),
        vulnerable_density_periods:
          Report.vulnerable_density_periods(density_commits, labels, lines, [
            2012..2020,
            2021..2025
          ]),
        vulnerable_by_size: Report.vulnerable_by_size(extended, labels)
      }
    end
  end

  defp manual_agreement(labels) do
    if File.exists?(@labeled) do
      manual = Sample.import(@labeled)
      Sample.agreement(manual, labels)
    end
  end

  defp write_all(summary) do
    File.mkdir_p!(@out)

    Enum.each(tables(summary) ++ volume_tables(summary.volume), fn table ->
      write_table(table)
    end)

    json = Jason.encode!(summary, pretty: true)
    File.write!(Path.join(@out, "summary.json"), json <> "\n")
    Mix.shell().info("tabelas e summary.json gravados em #{@out}/")
  end

  defp write_table({name, headers, rows, caption}) do
    latex = Latex.table(headers, rows, caption, "tab:#{name}")
    File.write!(Path.join(@out, "#{name}.tex"), latex)

    csv_rows = Enum.map(rows, fn row -> csv_row(row) end)
    CSV.write(Path.join(@out, "#{name}.csv"), headers, csv_rows)
  end

  defp tables(summary) do
    [
      {"match", ["métrica", "artigo", "humano (ativos)", "nosso"], match_rows(summary.match),
       "Comparação com o artigo original"},
      {"per_year", ["ano", "commits", "artigo (%)", "humano (%)", "nosso (%)"],
       per_year_rows(summary.per_year), "Proporção de commits vulneráveis por ano"},
      {"agreement",
       ["conjunto", "n", "VP", "FP", "FN", "VN", "precisão", "revocação", "F1", "kappa"],
       agreement_rows(summary), "Concordância entre o modelo e o rótulo humano"},
      {"ai_markers", ["ano", "com marcador", "vuln. com", "sem marcador", "vuln. sem"],
       ai_marker_rows(summary.ai.per_year), "Commits com e sem marcador de IA na mensagem"},
      {"ai_repo_files", ["repositório", "arquivo", "primeira data"],
       ai_file_rows(summary.ai.repo_files),
       "Arquivos de instrução para agentes de IA nos repositórios"},
      {"bots", ["ano", "commits de bots", "total"], bot_rows(summary.bots),
       "Commits de bots no período estendido"}
    ]
  end

  defp volume_tables(nil), do: []

  defp volume_tables(volume) do
    year_headers = [
      "ano",
      "commits",
      "repositórios",
      "autores",
      "arquivos",
      "arquivos por commit",
      "commits com ≥10 arquivos (%)",
      "mediana de linhas adicionadas",
      "linhas adicionadas",
      "linhas removidas",
      "commits por autor",
      "arquivos por autor",
      "linhas adicionadas por autor"
    ]

    [
      {"volume", year_headers, volume_rows(volume.per_year),
       "Volume de alterações em arquivos Elixir por ano (histórico completo da branch padrão)"},
      {"volume_sem_analytics", year_headers, volume_rows(volume.without_analytics),
       "Volume de alterações por ano sem o repositório analytics"},
      {"volume_repos", ["repositório" | year_headers], volume_repo_rows(volume.per_repo),
       "Volume de alterações em arquivos Elixir por repositório e ano"},
      {"volume_trimestres", ["trimestre" | tl(year_headers)],
       volume_quarter_rows(volume.per_quarter),
       "Volume de alterações em arquivos Elixir por trimestre"},
      {"volume_autores_frequentes",
       [
         "ano",
         "autores com ≥10 commits",
         "commits deles (%)",
         "commits por autor",
         "arquivos por autor",
         "linhas adicionadas por autor",
         "autores com 1 commit (%)"
       ], frequent_rows(volume.frequent_authors),
       "Autores com dez commits ou mais no ano e o volume por autor"},
      {"volume_vulneraveis", ["ano", "vulneráveis", "linhas adicionadas", "por 10 mil linhas"],
       density_rows(volume.vulnerable_density),
       "Commits vulneráveis por 10 mil linhas Elixir adicionadas"},
      {"volume_vulneraveis_periodos",
       ["período", "vulneráveis", "linhas adicionadas", "por 10 mil linhas"],
       density_rows(volume.vulnerable_density_periods),
       "Commits vulneráveis por 10 mil linhas Elixir adicionadas, por período"},
      {"tamanho_vulneraveis", ["arquivos Elixir no commit", "commits", "vulneráveis", "(%)"],
       size_rows(volume.vulnerable_by_size),
       "Proporção de commits vulneráveis por tamanho do commit (2021 a 2025)"}
    ]
  end

  defp volume_rows(rows) do
    Enum.map(rows, fn row -> [row.year | volume_cells(row)] end)
  end

  defp volume_repo_rows(rows) do
    Enum.map(rows, fn row -> [row.repo, row.year | volume_cells(row)] end)
  end

  defp volume_quarter_rows(rows) do
    Enum.map(rows, fn row -> [row.quarter | volume_cells(row)] end)
  end

  defp frequent_rows(rows) do
    Enum.map(rows, fn row ->
      [
        row.year,
        row.authors,
        row.commits_pct,
        row.commits_per_author,
        row.files_per_author,
        row.added_per_author,
        row.single_commit_pct
      ]
    end)
  end

  defp density_rows(rows) do
    Enum.map(rows, fn row -> [row.name, row.vulnerable, row.added, row.per_10k_lines] end)
  end

  defp size_rows(rows) do
    Enum.map(rows, fn row -> [row.band, row.commits, row.vulnerable, row.proportion] end)
  end

  defp volume_cells(row) do
    [
      row.commits,
      row.repos,
      row.authors,
      row.files,
      row.files_per_commit,
      row.large_pct,
      row.median_added,
      row.added,
      row.deleted,
      row.commits_per_author,
      row.files_per_author,
      row.added_per_author
    ]
  end

  defp match_rows(rows) do
    Enum.map(rows, fn row ->
      [row.metric, row.paper, row.human_active, row.ours]
    end)
  end

  defp per_year_rows(rows) do
    Enum.map(rows, fn row ->
      [row.year, row.commits, row.paper, row.human_active, row.ours]
    end)
  end

  defp ai_marker_rows(rows) do
    Enum.map(rows, fn row ->
      [row.year, row.with_marker, row.vulnerable_with, row.without_marker, row.vulnerable_without]
    end)
  end

  defp ai_file_rows(rows) do
    Enum.map(rows, fn row ->
      [row.repo, row.file, Date.to_iso8601(row.first_added)]
    end)
  end

  defp bot_rows(rows) do
    Enum.map(rows, fn row ->
      [row.year, row.bots, row.total]
    end)
  end

  defp agreement_rows(summary) do
    agreement = summary.agreement

    sets = [
      ["avaliação (2017-2020)" | score_cells(agreement.eval)],
      ["desenvolvimento (2012-2016)" | score_cells(agreement.dev)],
      ["todos (2012-2020)" | score_cells(agreement.all)]
    ]

    manual =
      if summary.manual do
        [["amostra manual (2021-2025)" | manual_cells(summary.manual)]]
      else
        []
      end

    runs = [
      run_row("entre execuções (kappa médio)", agreement.runs.n, agreement.runs.mean_kappa),
      run_row("entre execuções (kappa mínimo)", agreement.runs.n, agreement.runs.min_kappa)
    ]

    sets ++ manual ++ runs
  end

  defp run_row(label, n, kappa) do
    [label, n, nil, nil, nil, nil, nil, nil, nil, kappa]
  end

  defp score_cells(scores) do
    confusion = scores.confusion

    [
      scores.n,
      confusion.true_pos,
      confusion.false_pos,
      confusion.false_neg,
      confusion.true_neg,
      scores.precision,
      scores.recall,
      scores.f1,
      scores.kappa
    ]
  end

  defp manual_cells(manual) do
    confusion = manual.confusion
    scores = Metrics.precision_recall_f1(confusion)

    [
      manual.n,
      confusion.true_pos,
      confusion.false_pos,
      confusion.false_neg,
      confusion.true_neg,
      scores.precision,
      scores.recall,
      scores.f1,
      manual.kappa
    ]
  end

  defp csv_row(cells) do
    Enum.map(cells, fn cell -> csv_cell(cell) end)
  end

  defp csv_cell(nil), do: ""
  defp csv_cell(value), do: to_string(value)
end
