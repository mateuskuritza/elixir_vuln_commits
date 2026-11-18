defmodule VulnCommits.Volume do
  alias VulnCommits.{Bots, Collect, Commit, CSV, Git, Metrics}

  @columns ~w(repo hash date year author_email bot elixir_files elixir_added elixir_deleted)
  @large 10
  @frequent 10

  def collect(repo_rows, opts) do
    Enum.flat_map(repo_rows, fn row -> collect_repo(row, opts) end)
  end

  defp collect_repo(row, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)
    ref = Collect.branch_ref(row.dir, row.default_branch)
    entries = Git.log(row.dir, ref, no_merges: true, since: since, until: until)

    results =
      Task.async_stream(entries, fn entry -> measure(entry, row) end,
        max_concurrency: 4,
        timeout: :infinity
      )

    measured = Enum.map(results, fn {:ok, measured_row} -> measured_row end)
    Enum.reject(measured, fn measured_row -> measured_row.files == 0 end)
  end

  defp measure(entry, row) do
    numstat = Git.numstat(row.dir, entry.hash)
    commit = %Commit{author_name: entry.author_name, author_email: entry.author_email}
    Map.merge(lines_of(numstat), identity(entry, row.name, Bots.bot?(commit)))
  end

  defp identity(entry, repo, bot) do
    %{
      repo: repo,
      hash: entry.hash,
      date: entry.date,
      year: entry.date.year,
      author_email: entry.author_email,
      bot: bot
    }
  end

  def lines_of(numstat) do
    elixir_entries = Enum.filter(numstat, fn entry -> Commit.elixir_file?(entry.path) end)

    %{
      files: length(elixir_entries),
      added: sum(elixir_entries, fn entry -> entry.added end),
      deleted: sum(elixir_entries, fn entry -> entry.deleted end)
    }
  end

  def write(rows, path) do
    cells =
      Enum.map(rows, fn row ->
        [
          row.repo,
          row.hash,
          Date.to_iso8601(row.date),
          to_string(row.year),
          row.author_email,
          to_string(row.bot),
          to_string(row.files),
          to_string(row.added),
          to_string(row.deleted)
        ]
      end)

    CSV.write(path, @columns, cells)
  end

  def load(path) do
    rows = CSV.read(path)

    Enum.map(rows, fn row ->
      %{
        repo: row["repo"],
        hash: row["hash"],
        date: Date.from_iso8601!(row["date"]),
        year: String.to_integer(row["year"]),
        author_email: row["author_email"],
        bot: row["bot"] == "true",
        files: String.to_integer(row["elixir_files"]),
        added: String.to_integer(row["elixir_added"]),
        deleted: String.to_integer(row["elixir_deleted"])
      }
    end)
  end

  def by_hash(rows), do: Map.new(rows, fn row -> {row.hash, row} end)

  def per_year(rows, years) do
    by_year = Enum.group_by(humans(rows), fn row -> row.year end)

    Enum.map(years, fn year ->
      group = Map.get(by_year, year, [])
      Map.put(stats(group), :year, year)
    end)
  end

  def per_repo(rows, years) do
    groups = Enum.group_by(humans(rows), fn row -> {row.repo, row.year} end)
    repos = Enum.uniq(Enum.map(rows, fn row -> row.repo end))

    for repo <- Enum.sort(repos), year <- years do
      group = Map.get(groups, {repo, year}, [])
      row = Map.put(stats(group), :year, year)
      Map.put(row, :repo, repo)
    end
  end

  def per_quarter(rows) do
    by_quarter = Enum.group_by(humans(rows), fn row -> quarter(row.date) end)

    Enum.map(Enum.sort(by_quarter), fn {label, group} ->
      Map.put(stats(group), :quarter, label)
    end)
  end

  defp quarter(date), do: "#{date.year}T#{div(date.month - 1, 3) + 1}"

  def without_repo(rows, repo, years) do
    others = Enum.reject(rows, fn row -> row.repo == repo end)
    per_year(others, years)
  end

  defp humans(rows), do: Enum.reject(rows, fn row -> row.bot end)

  defp stats(rows) do
    total = length(rows)
    files = sum(rows, fn row -> row.files end)
    added = Enum.map(rows, fn row -> row.added end)
    authors = Enum.uniq(Enum.map(rows, fn row -> row.author_email end))
    repos = Enum.uniq(Enum.map(rows, fn row -> row.repo end))
    large = Enum.count(rows, fn row -> row.files >= @large end)

    %{
      commits: total,
      repos: length(repos),
      authors: length(authors),
      files: files,
      files_per_commit: mean(files, total),
      large_pct: Metrics.proportion(large, total),
      median_added: median(added),
      added: Enum.sum(added),
      deleted: sum(rows, fn row -> row.deleted end),
      commits_per_author: mean(total, length(authors)),
      files_per_author: mean(files, length(authors)),
      added_per_author: mean(Enum.sum(added), length(authors))
    }
  end

  def frequent_authors(rows, years) do
    by_year = Enum.group_by(humans(rows), fn row -> row.year end)

    Enum.map(years, fn year ->
      group = Map.get(by_year, year, [])
      by_author = Enum.group_by(group, fn row -> row.author_email end)
      frequent = Enum.filter(by_author, fn {_email, commits} -> length(commits) >= @frequent end)
      frequent_rows = Enum.flat_map(frequent, fn {_email, commits} -> commits end)
      authors = length(frequent)
      single = Enum.count(by_author, fn {_email, commits} -> length(commits) == 1 end)

      %{
        year: year,
        authors: authors,
        single_commit_pct: Metrics.proportion(single, map_size(by_author)),
        commits_pct: Metrics.proportion(length(frequent_rows), length(group)),
        commits_per_author: mean(length(frequent_rows), authors),
        files_per_author: mean(sum(frequent_rows, fn row -> row.files end), authors),
        added_per_author: mean(sum(frequent_rows, fn row -> row.added end), authors)
      }
    end)
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
