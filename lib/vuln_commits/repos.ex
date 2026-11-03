# ferramenta 1: resolve os repositórios do artigo (clone, github) e decide quais seguem ativos
defmodule VulnCommits.Repos do
  alias VulnCommits.{Bots, Commit, CSV, Git, GitHub}

  @columns ~w(name owner_repo dir stars archived default_branch head_at_collection
              hashes_expected hashes_found elixir_commits_2025 elixir_commits_2026
              last_elixir_commit active collected_at)a

  # as listas já vêm filtradas (sem bot, com arquivo elixir)
  def active?(commits_2025, commits_2026) do
    length(commits_2025) > 1 or length(commits_2026) >= 1
  end

  def resolve_all(dataset_commits, opts) do
    opts = with_defaults(opts)
    by_repo = Enum.group_by(dataset_commits, & &1.repo, & &1.hash)

    Enum.map(Enum.sort(Map.keys(by_repo)), fn name ->
      resolve(name, Map.fetch!(by_repo, name), opts)
    end)
  end

  defp with_defaults(opts) do
    clone_dir = Keyword.get(opts, :clone_dir, "repos")

    [
      clone_dir: clone_dir,
      repo_map: load_repo_map(),
      clone_fun: &clone_or_update/2,
      info_fun: &GitHub.repo_info/1
    ]
    |> Keyword.merge(opts)
  end

  defp load_repo_map do
    {map, _bindings} = Code.eval_file(Path.join(:code.priv_dir(:vuln_commits), "repo_map.exs"))
    map
  end

  defp resolve(name, hashes, opts) do
    owner_repo = Map.fetch!(opts[:repo_map], name)
    dir = opts[:clone_fun].(owner_repo, Path.join(opts[:clone_dir], name))

    info = repo_info(owner_repo, dir, opts[:info_fun])
    ref = branch_ref(dir, info.default_branch)

    missing = Enum.reject(hashes, &Git.object_exists?(dir, &1))
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

  # se a api falhar, a branch padrão vem do próprio clone
  defp repo_info(owner_repo, dir, info_fun) do
    case info_fun.(owner_repo) do
      {:ok, info} ->
        info

      {:error, reason} ->
        IO.puts(:stderr, "aviso: github falhou para #{owner_repo} (#{inspect(reason)})")
        %{stars: 0, archived: false, default_branch: Git.default_branch(dir)}
    end
  end

  # clone sem checkout só tem a branch no origin depois de atualizar; no repo de teste é local
  defp branch_ref(dir, branch) do
    remote = "origin/" <> branch
    if Git.object_exists?(dir, remote), do: remote, else: branch
  end

  defp warn_missing(_name, []), do: :ok

  defp warn_missing(name, missing) do
    IO.puts(:stderr, "aviso: #{name} sem #{length(missing)} hash(es): #{Enum.join(missing, " ")}")
  end

  # clone completo; se a pasta já existe só atualiza
  defp clone_or_update(owner_repo, dir) do
    result = if File.dir?(dir), do: Git.update(dir), else: Git.clone(owner_repo, dir)

    case result do
      :ok -> dir
      {:error, out} -> raise "clone de #{owner_repo} falhou: #{out}"
    end
  end

  # commit conta se não é merge, não é bot e mexe em arquivo elixir
  defp elixir_commits(dir, ref, year) do
    range = [since: Date.new!(year, 1, 1), until: Date.new!(year, 12, 31), no_merges: true]

    dir
    |> Git.log(ref, range)
    |> Enum.reject(&bot?/1)
    |> Task.async_stream(&{&1, Git.files(dir, &1.hash)},
      max_concurrency: System.schedulers_online(),
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, pair} -> pair end)
    |> Enum.filter(fn {_commit, files} -> Enum.any?(files, &Commit.elixir_file?/1) end)
    |> Enum.map(fn {commit, _files} -> commit end)
  end

  defp bot?(commit) do
    Bots.bot?(%Commit{author_name: commit.author_name, author_email: commit.author_email})
  end

  defp last_date([]), do: nil
  defp last_date(commits), do: commits |> Enum.map(& &1.date) |> Enum.max(Date)

  def active(rows), do: Enum.filter(rows, & &1.active)

  def write(path, rows) do
    CSV.write(path, Enum.map(@columns, &Atom.to_string/1), Enum.map(rows, &to_csv_row/1))
  end

  defp to_csv_row(row), do: Enum.map(@columns, &(row |> Map.fetch!(&1) |> to_text()))

  defp to_text(nil), do: ""
  defp to_text(%Date{} = date), do: Date.to_iso8601(date)
  defp to_text(value), do: to_string(value)

  def load(path), do: path |> CSV.read() |> Enum.map(&from_csv_row/1)

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
