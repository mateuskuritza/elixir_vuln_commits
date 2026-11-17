defmodule VulnCommits.Dataset do
  alias VulnCommits.{Commit, CSV, Metrics}

  def load(path) do
    rows = CSV.read(path)
    rows_by_hash = Enum.group_by(rows, fn row -> row["HASH"] end)
    commits = Enum.map(rows_by_hash, fn {_hash, commit_rows} -> build_commit(commit_rows) end)
    Enum.sort_by(commits, fn commit -> {commit.date, commit.hash} end)
  end

  defp build_commit([first | _] = rows) do
    paths = Enum.map(rows, fn row -> relative_path(row) end)
    files = Enum.sort(paths)
    date = parse_date(first["TIMESTAMP"])

    %Commit{
      repo: Path.basename(first["REPO"]),
      hash: first["HASH"],
      date: date,
      year: date.year,
      message: first["MESSAGE_TEXT"],
      files: files,
      elixir_files: files,
      human_label: label(first["SECURITY_STATUS"]),
      period: :original
    }
  end

  defp relative_path(%{"REPO" => repo, "FILE_PATH" => path}) do
    String.replace_prefix(path, repo <> "/", "")
  end

  defp parse_date(timestamp) do
    day = String.slice(timestamp, 0, 10)
    Date.from_iso8601!(day)
  end

  defp label("VULNERABLE"), do: :vulnerable
  defp label("NEUTRAL"), do: :neutral

  def summary(commits) do
    vulnerable = Enum.filter(commits, fn commit -> commit.human_label == :vulnerable end)
    vulnerable_repos = Enum.map(vulnerable, fn commit -> commit.repo end)
    unique_vulnerable_repos = Enum.uniq(vulnerable_repos)

    %{
      commits: length(commits),
      vulnerable: length(vulnerable),
      files: count_files(commits),
      files_in_vulnerable: count_files(vulnerable),
      repos_with_vulnerable: length(unique_vulnerable_repos)
    }
  end

  defp count_files(commits) do
    repo_files = Enum.flat_map(commits, fn commit -> files_with_repo(commit) end)
    unique_files = Enum.uniq(repo_files)
    length(unique_files)
  end

  defp files_with_repo(commit) do
    Enum.map(commit.files, fn file -> {commit.repo, file} end)
  end

  def per_year(commits) do
    commits_by_year = Enum.group_by(commits, fn commit -> Commit.year_of(commit) end)

    Map.new(commits_by_year, fn {year, year_commits} ->
      {year, year_stats(year_commits)}
    end)
  end

  defp year_stats(year_commits) do
    total = length(year_commits)

    vulnerable =
      Enum.count(year_commits, fn commit -> commit.human_label == :vulnerable end)

    %{
      commits: total,
      vulnerable: vulnerable,
      proportion: Metrics.proportion(vulnerable, total)
    }
  end

  def repo_names(commits) do
    names = Enum.map(commits, fn commit -> commit.repo end)
    unique_names = Enum.uniq(names)
    Enum.sort(unique_names)
  end
end
