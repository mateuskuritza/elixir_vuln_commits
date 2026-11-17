defmodule VulnCommits.Sample do
  alias VulnCommits.CSV
  alias VulnCommits.Metrics
  alias VulnCommits.Judge.Prompt

  @columns [
    "repo",
    "hash",
    "url",
    "date",
    "message",
    "elixir_files",
    "diff_excerpt",
    "label",
    "cia",
    "notes"
  ]
  @excerpt_bytes 3000
  @default_seed {20_261_021, 1, 2}

  def pick(candidates, opts \\ []) do
    n = Keyword.get(opts, :n, 80)
    seed = Keyword.get(opts, :seed, @default_seed)
    :rand.seed(:exsss, seed)

    groups = Enum.group_by(candidates, fn commit -> {commit.repo, commit.year} end)
    strata = Enum.sort_by(groups, fn {key, _commits} -> key end)

    quotas = allocate(strata, n)
    numbered_strata = Enum.with_index(strata)

    chosen =
      Enum.flat_map(numbered_strata, fn {{_key, commits}, index} ->
        by_hash = Enum.sort_by(commits, fn commit -> commit.hash end)
        shuffled = Enum.shuffle(by_hash)
        Enum.take(shuffled, Map.fetch!(quotas, index))
      end)

    sort(chosen)
  end

  defp allocate(strata, n) do
    sizes = Enum.map(strata, fn {_key, commits} -> length(commits) end)
    total = Enum.sum(sizes)
    numbered_strata = Enum.with_index(strata)

    rows =
      Enum.map(numbered_strata, fn {{_key, commits}, index} ->
        share = n * length(commits)
        %{index: index, floor: div(share, total), rest: rem(share, total)}
      end)

    floors = Enum.map(rows, fn row -> row.floor end)
    leftover = n - Enum.sum(floors)

    largest_rest_first = Enum.sort_by(rows, fn row -> {-row.rest, row.index} end)
    winner_rows = Enum.take(largest_rest_first, leftover)
    winners = Enum.map(winner_rows, fn row -> row.index end)

    Map.new(rows, fn row ->
      if row.index in winners do
        {row.index, row.floor + 1}
      else
        {row.index, row.floor}
      end
    end)
  end

  defp sort(commits) do
    Enum.sort_by(commits, fn commit ->
      {commit.repo, Date.to_iso8601(commit.date), commit.hash}
    end)
  end

  def export(commits, repo_rows, path) do
    dirs = Map.new(repo_rows, fn repo -> {repo.name, repo.dir} end)
    owners = Map.new(repo_rows, fn repo -> {repo.name, repo.owner_repo} end)

    rows =
      Enum.map(commits, fn commit ->
        owner_repo = Map.fetch!(owners, commit.repo)
        dir = Map.fetch!(dirs, commit.repo)

        [
          commit.repo,
          commit.hash,
          "https://github.com/#{owner_repo}/commit/#{commit.hash}",
          Date.to_iso8601(commit.date),
          commit.message,
          Enum.join(commit.elixir_files, "|"),
          excerpt(commit, dir),
          "",
          "",
          ""
        ]
      end)

    CSV.write(path, @columns, rows)
  end

  defp excerpt(commit, dir) do
    diff = Prompt.diff_for(commit, dir)
    Prompt.truncate(diff, @excerpt_bytes)
  end

  def import(path) do
    rows = CSV.read(path)

    bad_rows = Enum.filter(rows, fn row -> parse_label(row["label"]) == :error end)
    bad = Enum.map(bad_rows, fn row -> row["hash"] end)

    if bad != [] do
      raise ArgumentError,
            "label vazio ou inválido em #{length(bad)} linha(s): #{Enum.join(bad, " ")}"
    end

    Enum.map(rows, fn row ->
      %{hash: row["hash"], label: parse_label(row["label"]), cia: blank_to_nil(row["cia"])}
    end)
  end

  defp parse_label(nil), do: :error

  defp parse_label(text) do
    clean = String.upcase(String.trim(text))

    case clean do
      "VULNERABLE" -> :vulnerable
      "NEUTRAL" -> :neutral
      _ -> :error
    end
  end

  defp blank_to_nil(nil), do: nil

  defp blank_to_nil(text) do
    if String.trim(text) == "" do
      nil
    else
      text
    end
  end

  def agreement(manual, model_labels) do
    pairs =
      Enum.map(manual, fn row ->
        {row.label, model_final(model_labels, row.hash)}
      end)

    %{
      kappa: Metrics.cohen_kappa(pairs),
      confusion: Metrics.confusion(pairs),
      n: length(pairs)
    }
  end

  defp model_final(model_labels, hash) do
    case Map.fetch(model_labels, hash) do
      {:ok, %{final: :undecided}} -> :neutral
      {:ok, %{final: final}} -> final
      :error -> raise ArgumentError, "sem rótulo do modelo para o hash #{hash}"
    end
  end
end
