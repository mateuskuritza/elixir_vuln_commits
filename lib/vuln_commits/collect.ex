defmodule VulnCommits.Collect do
  alias VulnCommits.{AiMarkers, Bots, Commit, CSV, Git, Keywords}

  @columns ~w(period repo hash date year author_name author_email merge keyword_hit keywords
              bot ai_markers human_label files elixir_files message)

  @marker_columns ~w(repo file first_added)

  def enrich(%Commit{} = commit) do
    steps = [&with_keywords/1, &with_bot/1, &with_ai/1, &with_year/1]
    Enum.reduce(steps, commit, fn step, acc -> step.(acc) end)
  end

  defp with_keywords(commit) do
    keywords = Keywords.match(commit.message)
    %{commit | keyword_hit: keywords != [], keywords: keywords}
  end

  defp with_bot(commit), do: %{commit | bot: Bots.bot?(commit)}

  defp with_ai(commit), do: %{commit | ai_markers: AiMarkers.in_message(commit.message)}

  defp with_year(commit), do: %{commit | year: Commit.year_of(commit)}

  def original(dataset_commits, repo_rows) do
    dirs = Map.new(repo_rows, fn row -> {row.name, row.dir} end)

    known_commits =
      Enum.filter(dataset_commits, fn commit -> Map.has_key?(dirs, commit.repo) end)

    git_commits =
      Enum.map(known_commits, fn commit -> from_git(commit, Map.fetch!(dirs, commit.repo)) end)

    Enum.map(git_commits, fn commit -> enrich(commit) end)
  end

  defp from_git(commit, dir) do
    if Git.object_exists?(dir, commit.hash) do
      info = Git.show_message(dir, commit.hash)

      %{
        commit
        | message: info.message,
          author_name: info.author_name,
          author_email: info.author_email,
          merge?: info.merge?
      }
    else
      commit
    end
  end

  def extended(repo_rows, opts) do
    Enum.flat_map(repo_rows, fn row -> extended_repo(row, opts) end)
  end

  defp extended_repo(row, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)
    ref = branch_ref(row.dir, row.default_branch)

    period = Keyword.get(opts, :period, :extended)
    log_entries = Git.log(row.dir, ref, no_merges: true, since: since, until: until)

    results =
      Task.async_stream(log_entries, fn entry -> fetch_files(entry, row, period) end,
        max_concurrency: 4,
        timeout: :infinity
      )

    commits = Enum.map(results, fn {:ok, commit} -> commit end)
    elixir_commits = Enum.reject(commits, fn commit -> commit.elixir_files == [] end)
    Enum.map(elixir_commits, fn commit -> enrich(commit) end)
  end

  defp fetch_files(log_entry, row, period) do
    files = Git.files(row.dir, log_entry.hash)

    %Commit{
      repo: row.name,
      hash: log_entry.hash,
      date: log_entry.date,
      author_name: log_entry.author_name,
      author_email: log_entry.author_email,
      message: log_entry.message,
      files: files,
      elixir_files: Enum.filter(files, fn file -> Commit.elixir_file?(file) end),
      merge?: log_entry.merge?,
      period: period,
      human_label: nil
    }
  end

  # commits de 2012-2020 da branch padrão que não estão no dataset original.
  # o elixir teve o histórico reescrito, então além do hash compara autor, data e 1a linha
  def complement(repo_rows, original, opts) do
    all = extended(repo_rows, Keyword.put(opts, :period, :complement))
    drop_known(all, original)
  end

  def drop_known(commits, original) do
    hashes = MapSet.new(original, fn commit -> commit.hash end)
    keys = MapSet.new(original, fn commit -> same_commit_key(commit) end)

    Enum.reject(commits, fn commit ->
      MapSet.member?(hashes, commit.hash) or MapSet.member?(keys, same_commit_key(commit))
    end)
  end

  defp same_commit_key(commit) do
    first_line = commit.message |> String.split("\n") |> hd() |> String.trim()
    {commit.repo, commit.author_email, commit.date, first_line}
  end

  def merges_excluded(row, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)
    ref = branch_ref(row.dir, row.default_branch)

    all = Git.log(row.dir, ref, no_merges: false, since: since, until: until)
    plain = Git.log(row.dir, ref, no_merges: true, since: since, until: until)
    length(all) - length(plain)
  end

  def branch_ref(dir, branch) do
    remote = "origin/" <> branch

    if Git.object_exists?(dir, remote) do
      remote
    else
      branch
    end
  end

  def repo_markers(repo_rows) do
    Enum.flat_map(repo_rows, fn row -> markers_of_repo(row) end)
  end

  defp markers_of_repo(row) do
    found =
      Enum.map(AiMarkers.repo_files(), fn file ->
        %{repo: row.name, file: file, first_added: Git.first_added(row.dir, file)}
      end)

    Enum.filter(found, fn marker -> marker.first_added != nil end)
  end

  def write_markers(markers, path) do
    rows =
      Enum.map(markers, fn marker ->
        [marker.repo, marker.file, Date.to_iso8601(marker.first_added)]
      end)

    CSV.write(path, @marker_columns, rows)
  end

  def write(commits, path) do
    rows = Enum.map(commits, fn commit -> to_row(commit) end)
    CSV.write(path, @columns, rows)
  end

  defp to_row(commit) do
    [
      to_text(commit.period),
      commit.repo,
      commit.hash,
      Date.to_iso8601(commit.date),
      to_string(commit.year),
      to_text(commit.author_name),
      to_text(commit.author_email),
      to_string(commit.merge?),
      to_string(commit.keyword_hit),
      Enum.join(commit.keywords, "|"),
      to_string(commit.bot),
      Enum.join(commit.ai_markers, "|"),
      to_text(commit.human_label),
      Enum.join(commit.files, "|"),
      Enum.join(commit.elixir_files, "|"),
      to_text(commit.message)
    ]
  end

  defp to_text(nil), do: ""
  defp to_text(value), do: to_string(value)

  def load(path) do
    rows = CSV.read(path)
    Enum.map(rows, fn row -> from_row(row) end)
  end

  defp from_row(row) do
    %Commit{
      period: atom(row["period"]),
      repo: row["repo"],
      hash: row["hash"],
      date: Date.from_iso8601!(row["date"]),
      year: String.to_integer(row["year"]),
      author_name: blank_to_nil(row["author_name"]),
      author_email: blank_to_nil(row["author_email"]),
      merge?: row["merge"] == "true",
      keyword_hit: row["keyword_hit"] == "true",
      keywords: split(row["keywords"]),
      bot: row["bot"] == "true",
      ai_markers: split(row["ai_markers"]),
      human_label: atom(row["human_label"]),
      files: split(row["files"]),
      elixir_files: split(row["elixir_files"]),
      message: row["message"]
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(text), do: text

  defp atom(""), do: nil
  defp atom(text), do: String.to_atom(text)

  defp split(""), do: []
  defp split(text), do: String.split(text, "|")
end
