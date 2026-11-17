defmodule Mix.Tasks.Vuln.Repos do
  use Mix.Task

  alias VulnCommits.{Dataset, Repos}

  @shortdoc "Clona os repositórios do artigo e grava data/repos.csv"

  @dataset "data/figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv"
  @output "data/repos.csv"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    commits = Dataset.load(@dataset)
    rows = Repos.resolve_all(commits, today: Date.utc_today())

    Repos.write(@output, rows)

    Mix.shell().info("name  owner_repo  archived  2025  2026  ativo  hashes")
    Enum.each(rows, fn row -> print_row(row) end)

    active = Enum.count(rows, fn row -> row.active end)
    Mix.shell().info("\nativos: #{active} de #{length(rows)}")
  end

  defp print_row(row) do
    Mix.shell().info(
      "#{row.name}  #{row.owner_repo}  #{row.archived}  #{row.elixir_commits_2025}  " <>
        "#{row.elixir_commits_2026}  #{row.active}  #{row.hashes_found}/#{row.hashes_expected}"
    )
  end
end
