defmodule Mix.Tasks.Vuln.Sample do
  use Mix.Task

  alias VulnCommits.{Collect, CSV, Judge, Repos, Sample}
  alias VulnCommits.Judge.{Batch, Prompt, Store}

  @shortdoc "Amostra manual de 80 commits: mix vuln.sample export | import"

  @commits "data/commits.csv"
  @repos "data/repos.csv"
  @sample "data/sample_80.csv"
  @labeled "data/sample_80_labeled.csv"
  @judgments "data/judgments.jsonl"
  @agreement "out/manual_agreement.csv"

  @impl Mix.Task
  def run(["export"]), do: export()
  def run(["import"]), do: import_labels()

  def run(_args) do
    Mix.raise("use mix vuln.sample export | import")
  end

  defp export do
    commits = Collect.load(@commits)
    repo_rows = Repos.load(@repos)
    candidates = Judge.candidates(commits, :extended, years: nil)
    picked = Sample.pick(candidates, n: 80)

    Sample.export(picked, repo_rows, @sample)

    Mix.shell().info("candidatos do periodo estendido: #{length(candidates)}")
    Mix.shell().info("amostra: #{length(picked)} commits -> #{@sample}")
    print_counts("por repo", picked, fn commit -> commit.repo end)
    print_counts("por ano", picked, fn commit -> commit.year end)
  end

  defp print_counts(title, commits, key_fun) do
    Mix.shell().info("#{title}:")

    counts = Enum.frequencies_by(commits, key_fun)
    sorted = Enum.sort(counts)

    Enum.each(sorted, fn {key, count} ->
      Mix.shell().info("  #{key}: #{count}")
    end)
  end

  defp import_labels do
    if File.exists?(@labeled) do
      manual = Sample.import(@labeled)
      hashes = MapSet.new(manual, fn row -> row.hash end)

      commits = Collect.load(@commits)
      candidates = Judge.candidates(commits, :extended, years: nil)

      sampled =
        Enum.filter(candidates, fn commit ->
          MapSet.member?(hashes, commit.hash)
        end)

      records = Store.load(@judgments)
      model_labels = Judge.labels(sampled, records, Batch.model(), Prompt.version())

      warn_unjudged(sampled, model_labels)
      result = Sample.agreement(manual, model_labels)
      write_agreement(result)

      Mix.shell().info("kappa: #{Float.round(result.kappa, 4)}")
      Mix.shell().info("n: #{result.n}")
      Mix.shell().info("confusao: #{inspect(result.confusion)}")
      Mix.shell().info("gravado em #{@agreement}")
    else
      Mix.shell().info(
        "#{@labeled} não existe ainda. copie #{@sample} para #{@labeled}, rotule e rode de novo."
      )
    end
  end

  defp warn_unjudged(sampled, labels) do
    count = Judge.unjudged(sampled, labels)

    if count > 0 do
      Mix.shell().info(
        "AVISO: #{count} candidatos com menos de 3 votos válidos; os números de 'nosso' ainda não são finais"
      )
    end
  end

  defp write_agreement(result) do
    confusion = result.confusion

    rows = [
      ["kappa", Float.round(result.kappa, 4)],
      ["n", result.n],
      ["true_pos", confusion.true_pos],
      ["false_pos", confusion.false_pos],
      ["false_neg", confusion.false_neg],
      ["true_neg", confusion.true_neg]
    ]

    CSV.write(@agreement, ["metric", "value"], rows)
  end
end
