# relatório final: tabelas em latex e csv, mais um summary.json com todos os números
defmodule Mix.Tasks.Vuln.Report do
  use Mix.Task

  alias VulnCommits.{Collect, CSV, Judge, Latex, Metrics, Report, Sample}
  alias VulnCommits.Judge.{OpenAI, Prompt, Store}

  @shortdoc "Gera as tabelas do relatório em out/ (use --dev para só a concordância de 2012-2016)"

  @commits "data/commits.csv"
  @markers "data/repo_markers.csv"
  @judgments "data/judgments.jsonl"
  @labeled "data/sample_80_labeled.csv"
  @out "out"

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} = OptionParser.parse(args, strict: [dev: :boolean])

    commits = Collect.load(@commits)
    original = Enum.filter(commits, &(&1.period == :original))
    extended = Enum.filter(commits, &(&1.period == :extended))

    records = Store.load(@judgments)
    labels = Judge.labels(commits, records, OpenAI.model(), Prompt.version())
    warn_if_empty(labels)

    candidates =
      Judge.candidates(commits, :original, years: nil) ++
        Judge.candidates(commits, :extended, years: nil)

    warn_unjudged(candidates, labels)

    agreement = Report.agreement(original, labels, extended)

    if opts[:dev] do
      print_dev(agreement.dev)
    else
      markers = load_markers()

      summary = %{
        model: OpenAI.model(),
        prompt_version: Prompt.version(),
        match: Report.match(original, labels),
        per_year: Report.per_year(original, extended, labels),
        agreement: agreement,
        manual: manual_agreement(labels),
        bots: Report.bots(extended),
        ai: Report.ai(extended, labels, markers)
      }

      write_all(summary)
    end
  end

  defp warn_if_empty(labels) do
    if Enum.all?(labels, fn {_hash, label} -> label.votes == [] end) do
      Mix.shell().info(
        "AVISO: sem julgamentos ainda (#{@judgments}). todo candidato conta como neutral."
      )
    end
  end

  defp warn_unjudged(candidates, labels) do
    n = Judge.unjudged(candidates, labels)

    if n > 0 do
      Mix.shell().info(
        "AVISO: #{n} candidatos com menos de 3 votos válidos; os números de 'nosso' ainda não são finais"
      )
    end
  end

  defp print_dev(dev) do
    c = dev.confusion
    Mix.shell().info("dev (2012-2016): n=#{dev.n}")
    Mix.shell().info("kappa: #{Float.round(dev.kappa, 4)}")
    Mix.shell().info("precisao: #{Float.round(dev.precision, 4)}")
    Mix.shell().info("revocacao: #{Float.round(dev.recall, 4)}")
    Mix.shell().info("f1: #{Float.round(dev.f1, 4)}")
    Mix.shell().info("confusao: #{inspect(c)}")
  end

  defp load_markers() do
    if File.exists?(@markers) do
      for row <- CSV.read(@markers) do
        %{
          repo: row["repo"],
          file: row["file"],
          first_added: Date.from_iso8601!(row["first_added"])
        }
      end
    else
      []
    end
  end

  # concordância com a amostra manual, só se a planilha rotulada existir
  defp manual_agreement(labels) do
    if File.exists?(@labeled) do
      @labeled |> Sample.import() |> Sample.agreement(labels)
    end
  end

  # --- tabelas ---

  defp write_all(summary) do
    File.mkdir_p!(@out)

    for {name, headers, rows, caption} <- tables(summary) do
      File.write!(
        Path.join(@out, "#{name}.tex"),
        Latex.table(headers, rows, caption, "tab:#{name}")
      )

      CSV.write(Path.join(@out, "#{name}.csv"), headers, Enum.map(rows, &csv_row/1))
    end

    File.write!(Path.join(@out, "summary.json"), Jason.encode!(summary, pretty: true) <> "\n")
    Mix.shell().info("tabelas e summary.json gravados em #{@out}/")
  end

  defp tables(s) do
    [
      {"match", ["métrica", "artigo", "humano (ativos)", "nosso"], match_rows(s.match),
       "Comparação com o artigo original"},
      {"per_year", ["ano", "commits", "artigo (%)", "humano (%)", "nosso (%)"],
       Enum.map(s.per_year, &[&1.year, &1.commits, &1.paper, &1.human_active, &1.ours]),
       "Proporção de commits vulneráveis por ano"},
      {"agreement",
       ["conjunto", "n", "VP", "FP", "FN", "VN", "precisão", "revocação", "F1", "kappa"],
       agreement_rows(s), "Concordância entre o modelo e o rótulo humano"},
      {"ai_markers", ["ano", "com marcador", "vuln. com", "sem marcador", "vuln. sem"],
       Enum.map(
         s.ai.per_year,
         &[&1.year, &1.with_marker, &1.vulnerable_with, &1.without_marker, &1.vulnerable_without]
       ), "Commits com e sem marcador de IA na mensagem"},
      {"ai_repo_files", ["repositório", "arquivo", "primeira data"],
       Enum.map(s.ai.repo_files, &[&1.repo, &1.file, Date.to_iso8601(&1.first_added)]),
       "Arquivos de instrução para agentes de IA nos repositórios"},
      {"bots", ["ano", "commits de bots", "total"],
       Enum.map(s.bots, &[&1.year, &1.bots, &1.total]), "Commits de bots no período estendido"}
    ]
  end

  defp match_rows(rows), do: Enum.map(rows, &[&1.metric, &1.paper, &1.human_active, &1.ours])

  defp agreement_rows(s) do
    a = s.agreement

    sets = [
      ["avaliação (2017-2020)" | score_cells(a.eval)],
      ["desenvolvimento (2012-2016)" | score_cells(a.dev)],
      ["todos (2012-2020)" | score_cells(a.all)]
    ]

    manual =
      if s.manual do
        [["amostra manual (2021-2025)" | manual_cells(s.manual)]]
      else
        []
      end

    runs = [
      [
        "entre execuções (kappa médio)",
        a.runs.n,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        a.runs.mean_kappa
      ],
      [
        "entre execuções (kappa mínimo)",
        a.runs.n,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        nil,
        a.runs.min_kappa
      ]
    ]

    sets ++ manual ++ runs
  end

  defp score_cells(s) do
    c = s.confusion
    [s.n, c.true_pos, c.false_pos, c.false_neg, c.true_neg, s.precision, s.recall, s.f1, s.kappa]
  end

  defp manual_cells(manual) do
    c = manual.confusion
    prf = Metrics.precision_recall_f1(c)

    [
      manual.n,
      c.true_pos,
      c.false_pos,
      c.false_neg,
      c.true_neg,
      prf.precision,
      prf.recall,
      prf.f1,
      manual.kappa
    ]
  end

  # csv guarda o número cru; nil vira célula vazia
  defp csv_row(cells), do: Enum.map(cells, &csv_cell/1)
  defp csv_cell(nil), do: ""
  defp csv_cell(value), do: to_string(value)
end
