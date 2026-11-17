defmodule VulnCommits.Dataset do
  alias VulnCommits.{Commit, CSV, Metrics}

  def load(path) do
    path
    |> CSV.read()
    |> Enum.group_by(& &1["HASH"])
    |> Enum.map(fn {_hash, rows} -> build_commit(rows) end)
    |> Enum.sort_by(&{&1.date, &1.hash})
  end

  defp build_commit([first | _] = rows) do
    files = rows |> Enum.map(&relative_path/1) |> Enum.sort()
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
    timestamp |> String.slice(0, 10) |> Date.from_iso8601!()
  end

  defp label("VULNERABLE"), do: :vulnerable
  defp label("NEUTRAL"), do: :neutral

  def summary(commits) do
    vulnerable = Enum.filter(commits, &(&1.human_label == :vulnerable))

    %{
      commits: length(commits),
      vulnerable: length(vulnerable),
      files: count_files(commits),
      files_in_vulnerable: count_files(vulnerable),
      repos_with_vulnerable: vulnerable |> Enum.map(& &1.repo) |> Enum.uniq() |> length()
    }
  end

  defp count_files(commits) do
    commits
    |> Enum.flat_map(fn c -> Enum.map(c.files, &{c.repo, &1}) end)
    |> Enum.uniq()
    |> length()
  end

  def per_year(commits) do
    commits
    |> Enum.group_by(&Commit.year_of/1)
    |> Map.new(fn {year, group} ->
      vulnerable = Enum.count(group, &(&1.human_label == :vulnerable))

      {year,
       %{
         commits: length(group),
         vulnerable: vulnerable,
         proportion: Metrics.proportion(vulnerable, length(group))
       }}
    end)
  end

  def repo_names(commits) do
    commits |> Enum.map(& &1.repo) |> Enum.uniq() |> Enum.sort()
  end
end
