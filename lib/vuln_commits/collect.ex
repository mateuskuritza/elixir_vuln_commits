# ferramenta 2: índice de commits dos dois períodos (original do artigo e estendido)
defmodule VulnCommits.Collect do
  alias VulnCommits.{AiMarkers, Bots, Commit, CSV, Git, Keywords}

  @columns ~w(period repo hash date year author_name author_email merge keyword_hit keywords
              bot ai_markers human_label files elixir_files message)

  @marker_columns ~w(repo file first_added)

  # pipeline: cada função recebe o commit e devolve o commit com mais um campo preenchido
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

  # commits do csv do artigo cujo repo está entre os ativos.
  # files, data, ano e rótulo ficam como o csv deu; a mensagem e o autor vêm do git.
  def original(dataset_commits, repo_rows) do
    dirs = Map.new(repo_rows, &{&1.name, &1.dir})

    dataset_commits
    |> Enum.filter(&Map.has_key?(dirs, &1.repo))
    |> Enum.map(&from_git(&1, Map.fetch!(dirs, &1.repo)))
    |> Enum.map(&enrich/1)
  end

  # se o git não lê o hash, fica a mensagem do csv e sem autor
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

  # histórico da branch padrão no intervalo, só commits sem merge que mexem em arquivo elixir
  def extended(repo_rows, opts) do
    Enum.flat_map(repo_rows, &extended_repo(&1, opts))
  end

  defp extended_repo(row, opts) do
    log_opts = [since: Keyword.fetch!(opts, :since), until: Keyword.fetch!(opts, :until)]
    ref = branch_ref(row.dir, row.default_branch)

    row.dir
    |> Git.log(ref, [no_merges: true] ++ log_opts)
    |> Task.async_stream(&fetch_files(&1, row), max_concurrency: 4, timeout: :infinity)
    |> Enum.map(fn {:ok, commit} -> commit end)
    |> Enum.reject(&(&1.elixir_files == []))
    |> Enum.map(&enrich/1)
  end

  defp fetch_files(log_entry, row) do
    files = Git.files(row.dir, log_entry.hash)

    %Commit{
      repo: row.name,
      hash: log_entry.hash,
      date: log_entry.date,
      author_name: log_entry.author_name,
      author_email: log_entry.author_email,
      message: log_entry.message,
      files: files,
      elixir_files: Enum.filter(files, &Commit.elixir_file?/1),
      merge?: log_entry.merge?,
      period: :extended,
      human_label: nil
    }
  end

  # quantos merges ficaram de fora do índice (só para imprimir)
  def merges_excluded(row, opts) do
    ref = branch_ref(row.dir, row.default_branch)
    range = [since: Keyword.fetch!(opts, :since), until: Keyword.fetch!(opts, :until)]

    all = Git.log(row.dir, ref, [no_merges: false] ++ range)
    plain = Git.log(row.dir, ref, [no_merges: true] ++ range)
    length(all) - length(plain)
  end

  # clone sem checkout só tem a branch atualizada no origin
  defp branch_ref(dir, branch) do
    remote = "origin/" <> branch
    if Git.object_exists?(dir, remote), do: remote, else: branch
  end

  # arquivos de instrução de IA que existem no histórico de cada repo, com a data de criação
  def repo_markers(repo_rows) do
    for row <- repo_rows,
        file <- AiMarkers.repo_files(),
        first_added = Git.first_added(row.dir, file),
        do: %{repo: row.name, file: file, first_added: first_added}
  end

  def write_markers(markers, path) do
    rows = Enum.map(markers, &[&1.repo, &1.file, Date.to_iso8601(&1.first_added)])
    CSV.write(path, @marker_columns, rows)
  end

  def write(commits, path) do
    CSV.write(path, @columns, Enum.map(commits, &to_row/1))
  end

  defp to_row(c) do
    [
      to_text(c.period),
      c.repo,
      c.hash,
      Date.to_iso8601(c.date),
      to_string(c.year),
      to_text(c.author_name),
      to_text(c.author_email),
      to_string(c.merge?),
      to_string(c.keyword_hit),
      Enum.join(c.keywords, "|"),
      to_string(c.bot),
      Enum.join(c.ai_markers, "|"),
      to_text(c.human_label),
      Enum.join(c.files, "|"),
      Enum.join(c.elixir_files, "|"),
      to_text(c.message)
    ]
  end

  defp to_text(nil), do: ""
  defp to_text(value), do: to_string(value)

  def load(path), do: path |> CSV.read() |> Enum.map(&from_row/1)

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

  # só vêm daqui valores conhecidos (original/extended, vulnerable/neutral)
  defp atom(""), do: nil
  defp atom(text), do: String.to_atom(text)

  defp split(""), do: []
  defp split(text), do: String.split(text, "|")
end
