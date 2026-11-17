defmodule VulnCommits.Volume do
  alias VulnCommits.{Commit, CSV, Git, Metrics}

  @columns ~w(repo hash elixir_added elixir_deleted)
  @years 2021..2025
  @large 10

  def collect(commits, dirs, numstat \\ &Git.numstat/2) do
    results =
      Task.async_stream(commits, fn commit -> lines_of(commit, dirs, numstat) end,
        max_concurrency: 4,
        timeout: :infinity
      )

    Enum.map(results, fn {:ok, row} -> row end)
  end

  defp lines_of(commit, dirs, numstat) do
    entries = numstat.(Map.fetch!(dirs, commit.repo), commit.hash)
    elixir_entries = Enum.filter(entries, fn entry -> Commit.elixir_file?(entry.path) end)

    %{
      repo: commit.repo,
      hash: commit.hash,
      added: sum(elixir_entries, fn entry -> entry.added end),
      deleted: sum(elixir_entries, fn entry -> entry.deleted end)
    }
  end

  def write(rows, path) do
    cells =
      Enum.map(rows, fn row ->
        [row.repo, row.hash, to_string(row.added), to_string(row.deleted)]
      end)

    CSV.write(path, @columns, cells)
  end

  def load(path) do
    rows = CSV.read(path)

    Map.new(rows, fn row ->
      lines = %{
        added: String.to_integer(row["elixir_added"]),
        deleted: String.to_integer(row["elixir_deleted"])
      }

      {row["hash"], lines}
    end)
  end

  def per_year(extended, lines) do
    by_year = Enum.group_by(humans(extended), fn commit -> commit.year end)

    Enum.map(@years, fn year ->
      group = Map.get(by_year, year, [])
      Map.put(stats(group, lines), :year, year)
    end)
  end

  def per_repo(extended, lines) do
    groups = Enum.group_by(humans(extended), fn commit -> {commit.repo, commit.year} end)
    repos = Enum.uniq(Enum.map(extended, fn commit -> commit.repo end))

    for repo <- Enum.sort(repos), year <- @years do
      group = Map.get(groups, {repo, year}, [])
      row = Map.put(stats(group, lines), :year, year)
      Map.put(row, :repo, repo)
    end
  end

  def per_quarter(extended, lines) do
    by_quarter = Enum.group_by(humans(extended), fn commit -> quarter(commit.date) end)

    Enum.map(Enum.sort(by_quarter), fn {label, group} ->
      Map.put(stats(group, lines), :quarter, label)
    end)
  end

  defp quarter(date), do: "#{date.year}T#{div(date.month - 1, 3) + 1}"

  def without_repo(extended, lines, repo) do
    others = Enum.reject(extended, fn commit -> commit.repo == repo end)
    per_year(others, lines)
  end

  defp humans(commits), do: Enum.reject(commits, fn commit -> commit.bot end)

  defp stats(commits, lines) do
    total = length(commits)
    file_counts = Enum.map(commits, fn commit -> length(commit.elixir_files) end)
    added = Enum.map(commits, fn commit -> Map.fetch!(lines, commit.hash).added end)
    deleted = Enum.map(commits, fn commit -> Map.fetch!(lines, commit.hash).deleted end)
    authors = Enum.uniq(Enum.map(commits, fn commit -> commit.author_email end))
    large = Enum.count(file_counts, fn count -> count >= @large end)

    %{
      commits: total,
      authors: length(authors),
      files: Enum.sum(file_counts),
      files_per_commit: mean(Enum.sum(file_counts), total),
      large_pct: Metrics.proportion(large, total),
      median_added: median(added),
      added: Enum.sum(added),
      deleted: Enum.sum(deleted)
    }
  end

  defp sum(list, fun), do: Enum.sum(Enum.map(list, fun))

  defp mean(_sum, 0), do: 0.0
  defp mean(sum, count), do: Float.round(sum / count, 2)

  def median([]), do: 0.0

  def median(values) do
    sorted = Enum.sort(values)
    count = length(sorted)
    middle = div(count, 2)

    if rem(count, 2) == 1 do
      Enum.at(sorted, middle) * 1.0
    else
      (Enum.at(sorted, middle - 1) + Enum.at(sorted, middle)) / 2
    end
  end
end
