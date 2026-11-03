defmodule Mix.Tasks.Vuln.Repos do
  use Mix.Task

  alias VulnCommits.{Dataset, Repos}

  @shortdoc "Clona os repositórios do artigo e grava data/repos.csv"

  @dataset "data/figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv"
  @output "data/repos.csv"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)

    rows =
      @dataset
      |> Dataset.load()
      |> Repos.resolve_all(today: Date.utc_today())

    Repos.write(@output, rows)

    Mix.shell().info("name  owner_repo  archived  2025  2026  ativo  hashes")
    Enum.each(rows, &print_row/1)
    Mix.shell().info("\nativos: #{Enum.count(rows, & &1.active)} de #{length(rows)}")
  end

  defp print_row(r) do
    Mix.shell().info(
      "#{r.name}  #{r.owner_repo}  #{r.archived}  #{r.elixir_commits_2025}  " <>
        "#{r.elixir_commits_2026}  #{r.active}  #{r.hashes_found}/#{r.hashes_expected}"
    )
  end
end
