defmodule VulnCommits.Repos do
  alias VulnCommits.{Bots, Commit, CSV, Git, GitHub}

  @columns [
    :name,
    :owner_repo,
    :dir,
    :stars,
    :archived,
    :default_branch,
    :head_at_collection,
    :hashes_expected,
    :hashes_found,
    :elixir_commits_2025,
    :elixir_commits_2026,
    :last_elixir_commit,
    :active,
    :collected_at
  ]

  def active?(commits_2025, commits_2026) do
    length(commits_2025) > 1 or length(commits_2026) >= 1
  end

  def resolve_all(dataset_commits, opts) do
    opts = with_defaults(opts)

    hashes_by_repo =
      Enum.group_by(dataset_commits, fn commit -> commit.repo end, fn commit -> commit.hash end)

    names = Enum.sort(Map.keys(hashes_by_repo))

    Enum.map(names, fn name ->
      resolve(name, Map.fetch!(hashes_by_repo, name), opts)
    end)
  end

  defp with_defaults(opts) do
    clone_dir = Keyword.get(opts, :clone_dir, "repos")

    defaults = [
      clone_dir: clone_dir,
      repo_map: load_repo_map(),
      clone_fun: fn owner_repo, dir -> clone_or_update(owner_repo, dir) end,
      info_fun: fn owner_repo -> GitHub.repo_info(owner_repo) end
    ]

    Keyword.merge(defaults, opts)
  end

  defp load_repo_map do
    priv_dir = :code.priv_dir(:vuln_commits)
    file = Path.join(priv_dir, "repo_map.exs")
    {map, _bindings} = Code.eval_file(file)
    map
  end

  defp resolve(name, hashes, opts) do
    owner_repo = Map.fetch!(opts[:repo_map], name)
    dir = opts[:clone_fun].(owner_repo, Path.join(opts[:clone_dir], name))

    info = repo_info(owner_repo, dir, opts[:info_fun])
    ref = branch_ref(dir, info.default_branch)

    missing = Enum.reject(hashes, fn hash -> Git.object_exists?(dir, hash) end)
    warn_missing(name, missing)

    commits_2025 = elixir_commits(dir, ref, 2025)
    commits_2026 = elixir_commits(dir, ref, 2026)

    %{
      name: name,
      owner_repo: owner_repo,
      dir: dir,
      stars: info.stars,
      archived: info.archived,
      default_branch: info.default_branch,
      head_at_collection: Git.head(dir, ref),
      hashes_expected: length(hashes),
      hashes_found: length(hashes) - length(missing),
      elixir_commits_2025: length(commits_2025),
      elixir_commits_2026: length(commits_2026),
      last_elixir_commit: last_date(commits_2025 ++ commits_2026),
      active: not info.archived and active?(commits_2025, commits_2026),
      collected_at: opts[:today]
    }
  end

  defp repo_info(owner_repo, dir, info_fun) do
    case info_fun.(owner_repo) do
      {:ok, info} ->
        info

      {:error, reason} ->
        IO.puts(:stderr, "aviso: github falhou para #{owner_repo} (#{inspect(reason)})")
        %{stars: 0, archived: false, default_branch: Git.default_branch(dir)}
    end
  end

  defp branch_ref(dir, branch) do
    remote = "origin/" <> branch

    if Git.object_exists?(dir, remote) do
      remote
    else
      branch
    end
  end

  defp warn_missing(_name, []), do: :ok

  defp warn_missing(name, missing) do
    IO.puts(:stderr, "aviso: #{name} sem #{length(missing)} hash(es): #{Enum.join(missing, " ")}")
  end

  defp clone_or_update(owner_repo, dir) do
    result =
      if File.dir?(dir) do
        Git.update(dir)
      else
        Git.clone(owner_repo, dir)
      end

    case result do
      :ok -> dir
      {:error, out} -> raise "clone de #{owner_repo} falhou: #{out}"
    end
  end

  defp elixir_commits(dir, ref, year) do
    range = [since: Date.new!(year, 1, 1), until: Date.new!(year, 12, 31), no_merges: true]

    log_entries = Git.log(dir, ref, range)
    human_entries = Enum.reject(log_entries, fn entry -> bot?(entry) end)

    results =
      Task.async_stream(human_entries, fn entry -> touches_elixir?(dir, entry) end,
        max_concurrency: System.schedulers_online(),
        timeout: :infinity
      )

    flags = Enum.map(results, fn {:ok, flag} -> flag end)
    pairs = Enum.zip(human_entries, flags)
    elixir_pairs = Enum.filter(pairs, fn {_entry, flag} -> flag end)
    Enum.map(elixir_pairs, fn {entry, _flag} -> entry end)
  end

  defp touches_elixir?(dir, entry) do
    files = Git.files(dir, entry.hash)
    Enum.any?(files, fn file -> Commit.elixir_file?(file) end)
  end

  defp bot?(commit) do
    Bots.bot?(%Commit{author_name: commit.author_name, author_email: commit.author_email})
  end

  defp last_date([]), do: nil

  defp last_date(commits) do
    dates = Enum.map(commits, fn commit -> commit.date end)
    Enum.max(dates, Date)
  end

  def active(rows), do: Enum.filter(rows, fn row -> row.active end)

  def write(path, rows) do
    headers = Enum.map(@columns, fn column -> Atom.to_string(column) end)
    csv_rows = Enum.map(rows, fn row -> to_csv_row(row) end)
    CSV.write(path, headers, csv_rows)
  end

  defp to_csv_row(row) do
    Enum.map(@columns, fn column -> to_text(Map.fetch!(row, column)) end)
  end

  defp to_text(nil), do: ""
  defp to_text(%Date{} = date), do: Date.to_iso8601(date)
  defp to_text(value), do: to_string(value)

  def load(path) do
    rows = CSV.read(path)
    Enum.map(rows, fn row -> from_csv_row(row) end)
  end

  defp from_csv_row(row) do
    %{
      name: row["name"],
      owner_repo: row["owner_repo"],
      dir: row["dir"],
      stars: String.to_integer(row["stars"]),
      archived: row["archived"] == "true",
      default_branch: row["default_branch"],
      head_at_collection: row["head_at_collection"],
      hashes_expected: String.to_integer(row["hashes_expected"]),
      hashes_found: String.to_integer(row["hashes_found"]),
      elixir_commits_2025: String.to_integer(row["elixir_commits_2025"]),
      elixir_commits_2026: String.to_integer(row["elixir_commits_2026"]),
      last_elixir_commit: parse_date(row["last_elixir_commit"]),
      active: row["active"] == "true",
      collected_at: parse_date(row["collected_at"])
    }
  end

  defp parse_date(""), do: nil
  defp parse_date(text), do: Date.from_iso8601!(text)
end
