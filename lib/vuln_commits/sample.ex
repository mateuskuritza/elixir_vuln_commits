defmodule VulnCommits.Sample do
  alias VulnCommits.{CSV, Metrics}
  alias VulnCommits.Judge.Prompt

  @columns ~w(repo hash url date message elixir_files diff_excerpt label cia notes)
  @excerpt_bytes 3000
  @default_seed {20_261_021, 1, 2}

  def pick(candidates, opts \\ []) do
    n = Keyword.get(opts, :n, 80)
    :rand.seed(:exsss, Keyword.get(opts, :seed, @default_seed))

    strata =
      candidates
      |> Enum.group_by(&{&1.repo, &1.year})
      |> Enum.sort_by(fn {key, _commits} -> key end)

    quotas = allocate(strata, n)

    strata
    |> Enum.with_index()
    |> Enum.flat_map(fn {{_key, commits}, i} ->
      commits
      |> Enum.sort_by(& &1.hash)
      |> Enum.shuffle()
      |> Enum.take(Map.fetch!(quotas, i))
    end)
    |> sort()
  end

  defp allocate(strata, n) do
    total = strata |> Enum.map(fn {_key, commits} -> length(commits) end) |> Enum.sum()

    rows =
      strata
      |> Enum.with_index()
      |> Enum.map(fn {{_key, commits}, i} ->
        share = n * length(commits)
        %{i: i, floor: div(share, total), rem: rem(share, total)}
      end)

    leftover = n - Enum.sum(Enum.map(rows, & &1.floor))

    winners =
      rows
      |> Enum.sort_by(&{-&1.rem, &1.i})
      |> Enum.take(leftover)
      |> MapSet.new(& &1.i)

    Map.new(rows, fn row ->
      extra = if MapSet.member?(winners, row.i), do: 1, else: 0
      {row.i, row.floor + extra}
    end)
  end

  defp sort(commits) do
    Enum.sort_by(commits, &{&1.repo, Date.to_iso8601(&1.date), &1.hash})
  end

  def export(commits, repo_rows, path) do
    dirs = Map.new(repo_rows, &{&1.name, &1.dir})
    owners = Map.new(repo_rows, &{&1.name, &1.owner_repo})

    rows =
      Enum.map(commits, fn c ->
        [
          c.repo,
          c.hash,
          "https://github.com/#{Map.fetch!(owners, c.repo)}/commit/#{c.hash}",
          Date.to_iso8601(c.date),
          c.message,
          Enum.join(c.elixir_files, "|"),
          excerpt(c, Map.fetch!(dirs, c.repo)),
          "",
          "",
          ""
        ]
      end)

    CSV.write(path, @columns, rows)
  end

  defp excerpt(commit, dir) do
    commit |> Prompt.diff_for(dir) |> Prompt.truncate(@excerpt_bytes)
  end

  def import(path) do
    rows = CSV.read(path)

    bad = for row <- rows, parse_label(row["label"]) == :error, do: row["hash"]

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
    case text |> String.trim() |> String.upcase() do
      "VULNERABLE" -> :vulnerable
      "NEUTRAL" -> :neutral
      _ -> :error
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(text), do: if(String.trim(text) == "", do: nil, else: text)

  def agreement(manual, model_labels) do
    pairs = Enum.map(manual, &{&1.label, model_final(model_labels, &1.hash)})

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
