defmodule Mix.Tasks.Vuln.Volume do
  use Mix.Task

  alias VulnCommits.{Collect, Repos, Volume}

  @shortdoc "Conta as linhas Elixir adicionadas e removidas por commit de 2021 a 2025 (data/volume.csv)"

  @repos "data/repos.csv"
  @commits "data/commits.csv"
  @volume "data/volume.csv"

  @impl Mix.Task
  def run(_args) do
    rows = Repos.load(@repos)
    dirs = Map.new(rows, fn row -> {row.name, row.dir} end)

    commits = Collect.load(@commits)
    extended = Enum.filter(commits, fn commit -> commit.period == :extended end)

    volume = Volume.collect(extended, dirs)
    Volume.write(volume, @volume)
    Mix.shell().info("#{length(volume)} commits gravados em #{@volume}")
  end
end
