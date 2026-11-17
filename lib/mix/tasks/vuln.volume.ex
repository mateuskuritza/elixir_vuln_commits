defmodule Mix.Tasks.Vuln.Volume do
  use Mix.Task

  alias VulnCommits.{Repos, Volume}

  @shortdoc "Conta arquivos e linhas Elixir por commit de 2012 a 2025 (data/volume.csv)"

  @repos "data/repos.csv"
  @volume "data/volume.csv"
  @range [since: ~D[2012-01-01], until: ~D[2025-12-31]]

  @impl Mix.Task
  def run(_args) do
    rows = Repos.active(Repos.load(@repos))
    volume = Volume.collect(rows, @range)
    Volume.write(volume, @volume)
    Mix.shell().info("#{length(volume)} commits gravados em #{@volume}")
  end
end
