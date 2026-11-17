defmodule Mix.Tasks.Vuln.Report do
  use Mix.Task

  alias VulnCommits.{Collect, CSV, Judge, Latex, Metrics, Report, Sample, Volume}
  alias VulnCommits.Judge.{Batch, Prompt, Store}

  @shortdoc "Gera as tabelas do relatório em out/ (use --dev para só a concordância de 2012-2016)"

  @commits "data/commits.csv"
  @markers "data/repo_markers.csv"
  @judgments "data/judgments.jsonl"
  @labeled "data/sample_80_labeled.csv"
  @volume "data/volume.csv"
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
        volume: volume(extended, labels)
      }

      write_all(summary)
    end
  end

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

  defp volume(extended, labels) do
    if File.exists?(@volume) do
      lines = Volume.load(@volume)

      %{
        per_year: Volume.per_year(extended, lines),
        per_repo: Volume.per_repo(extended, lines),
        per_quarter: Volume.per_quarter(extended, lines),
        without_analytics: Volume.without_repo(extended, lines, "analytics"),
        vulnerable_density: Report.vulnerable_density(extended, labels, lines),
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
      "autores",
      "arquivos",
      "arquivos por commit",
      "commits com ≥10 arquivos (%)",
      "mediana de linhas adicionadas",
      "linhas adicionadas",
      "linhas removidas"
    ]

    [
      {"volume", year_headers, volume_rows(volume.per_year),
       "Volume de alterações em arquivos Elixir por ano"},
      {"volume_sem_analytics", year_headers, volume_rows(volume.without_analytics),
       "Volume de alterações por ano sem o repositório analytics"},
      {"volume_repos", ["repositório" | year_headers], volume_repo_rows(volume.per_repo),
       "Volume de alterações em arquivos Elixir por repositório e ano"},
      {"volume_trimestres", ["trimestre" | tl(year_headers)],
       volume_quarter_rows(volume.per_quarter),
       "Volume de alterações em arquivos Elixir por trimestre"},
      {"volume_vulneraveis", ["ano", "vulneráveis", "linhas adicionadas", "por 10 mil linhas"],
       density_rows(volume.vulnerable_density),
       "Commits vulneráveis por 10 mil linhas Elixir adicionadas"},
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

  defp density_rows(rows) do
    Enum.map(rows, fn row -> [row.year, row.vulnerable, row.added, row.per_10k_lines] end)
  end

  defp size_rows(rows) do
    Enum.map(rows, fn row -> [row.band, row.commits, row.vulnerable, row.proportion] end)
  end

  defp volume_cells(row) do
    [
      row.commits,
      row.authors,
      row.files,
      row.files_per_commit,
      row.large_pct,
      row.median_added,
      row.added,
      row.deleted
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
