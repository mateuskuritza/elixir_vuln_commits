defmodule Mix.Tasks.Vuln.Collect do
  use Mix.Task

  alias VulnCommits.{Collect, Dataset, Repos}

  @shortdoc "Monta data/commits.csv (período original e estendido) e data/repo_markers.csv"

  @dataset "data/figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv"
  @repos "data/repos.csv"
  @commits "data/commits.csv"
  @markers "data/repo_markers.csv"
  @range [since: ~D[2021-01-01], until: ~D[2025-12-31]]

  @impl Mix.Task
  def run(_args) do
    all_rows = Repos.load(@repos)
    rows = Repos.active(all_rows)
    Mix.shell().info("repositórios ativos: #{length(rows)}")

    dataset = Dataset.load(@dataset)
    original = Collect.original(dataset, rows)
    Mix.shell().info("período original pronto: #{length(original)} commits")

    extended = Collect.extended(rows, @range)
    Mix.shell().info("período estendido pronto: #{length(extended)} commits")

    Collect.write(original ++ extended, @commits)
    markers = Collect.repo_markers(rows)
    Collect.write_markers(markers, @markers)

    print_period("original", original)
    print_period("estendido", extended)
    print_merges(rows)
    Mix.shell().info("\narquivos de IA no histórico: #{length(markers)}")
  end

  defp print_period(label, commits) do
    Mix.shell().info("\n== #{label}: #{summary(commits)}")

    groups = Enum.group_by(commits, fn commit -> commit.repo end)
    sorted_groups = Enum.sort(groups)

    Enum.each(sorted_groups, fn {repo, group} ->
      Mix.shell().info("  #{repo}: #{summary(group)}")
    end)
  end

  defp summary(commits) do
    candidates =
      Enum.count(commits, fn commit ->
        commit.keyword_hit and not commit.bot
      end)

    bots = Enum.count(commits, fn commit -> commit.bot end)
    "#{length(commits)} commits, #{candidates} candidatos, #{bots} bots"
  end

  defp print_merges(rows) do
    Mix.shell().info("\n== merges excluídos do estendido")

    Enum.each(rows, fn row ->
      Mix.shell().info("  #{row.name}: #{Collect.merges_excluded(row, @range)}")
    end)
  end
end
