defmodule Mix.Tasks.Vuln.Volume do
  use Mix.Task

  alias VulnCommits.{Collect, Repos, Volume}

  @shortdoc "Conta arquivos e linhas Elixir por commit (data/volume.csv e data/volume_original.csv)"

  @repos "data/repos.csv"
  @volume "data/volume.csv"
  @volume_original "data/volume_original.csv"
  @commits "data/commits.csv"
  @range [since: ~D[2012-01-01], until: ~D[2025-12-31]]

  @impl Mix.Task
  # sem argumento: as duas medições. "original": só os commits do dataset de 2012 a 2020
  def run(args) do
    rows = Repos.active(Repos.load(@repos))

    if args != ["original"] do
      volume = Volume.collect(rows, @range)
      Volume.write(volume, @volume)
      Mix.shell().info("#{length(volume)} commits gravados em #{@volume}")
    end

    original =
      Enum.filter(Collect.load(@commits), fn commit -> commit.period == :original end)

    measured = Volume.collect_commits(original, rows)
    Volume.write(measured, @volume_original)
    Mix.shell().info("#{length(measured)} commits gravados em #{@volume_original}")
  end
end
