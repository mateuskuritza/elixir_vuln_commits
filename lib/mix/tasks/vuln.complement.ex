defmodule Mix.Tasks.Vuln.Complement do
  use Mix.Task

  alias VulnCommits.{Collect, Repos}

  @shortdoc "Monta data/commits_complement.csv: commits de 2012-2020 fora do dataset original"

  @repos "data/repos.csv"
  @commits "data/commits.csv"
  @out "data/commits_complement.csv"
  @range [since: ~D[2012-01-01], until: ~D[2020-12-31]]

  @impl Mix.Task
  def run(_args) do
    rows = Repos.active(Repos.load(@repos))
    original = Enum.filter(Collect.load(@commits), fn commit -> commit.period == :original end)
    complement = Collect.complement(rows, original, @range)
    Collect.write(complement, @out)

    candidates = Enum.count(complement, fn commit -> commit.keyword_hit and not commit.bot end)
    bots = Enum.count(complement, fn commit -> commit.bot end)
    Mix.shell().info("#{length(complement)} commits, #{candidates} candidatos, #{bots} bots")
  end
end
