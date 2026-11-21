defmodule VulnCommits.Judge do
  alias VulnCommits.Commit
  alias VulnCommits.Vote
  alias VulnCommits.Judge.Anthropic
  alias VulnCommits.Judge.Prompt
  alias VulnCommits.Judge.Store

  @runs [1, 2, 3]
  @max_concurrency 4
  @progress_every 50

  def candidates(commits, period, opts) do
    years = Keyword.get(opts, :years)

    Enum.filter(commits, fn commit ->
      commit.keyword_hit and not commit.bot and commit.period == period and
        in_years?(commit.year, years)
    end)
  end

  defp in_years?(_year, nil), do: true
  defp in_years?(year, range), do: year in range

  def pending(candidates, done_set, model, version) do
    all_pairs =
      Enum.flat_map(candidates, fn commit ->
        Enum.map(@runs, fn run -> {commit, run} end)
      end)

    Enum.filter(all_pairs, fn {commit, run} ->
      key = {commit.hash, run, model, version}
      not MapSet.member?(done_set, key)
    end)
  end

  def run(pairs, opts) do
    model =
      case Keyword.fetch(opts, :model) do
        {:ok, model} -> model
        :error -> Anthropic.model()
      end

    version =
      case Keyword.fetch(opts, :version) do
        {:ok, version} -> version
        :error -> Prompt.version()
      end

    dirs = Keyword.fetch!(opts, :dirs)
    path = Keyword.fetch!(opts, :path)

    judge_fun =
      case Keyword.fetch(opts, :judge_fun) do
        {:ok, judge_fun} -> judge_fun
        :error -> default_judge(model, version)
      end

    total = length(pairs)

    judge_one = fn {commit, run} ->
      dir = Map.get(dirs, commit.repo)
      result = safe_judge(commit, dir, run, judge_fun)
      to_record(result, commit, run, model, version)
    end

    results =
      Task.async_stream(pairs, judge_one,
        max_concurrency: @max_concurrency,
        timeout: :infinity
      )

    numbered = Enum.with_index(results, 1)

    Enum.each(numbered, fn {{:ok, record}, number} ->
      Store.append(path, record)

      if rem(number, @progress_every) == 0 do
        IO.puts("julgados #{number} de #{total}")
      end
    end)

    IO.puts("julgados #{total} de #{total}")
    :ok
  end

  defp safe_judge(commit, dir, run, judge_fun) do
    try do
      judge_fun.(commit, dir, run)
    rescue
      error -> {:error, {:exception, Exception.message(error)}}
    end
  end

  defp default_judge(model, version) do
    system = Prompt.system(version)

    fn commit, dir, run ->
      diff = Prompt.diff_for(commit, dir)
      user = Prompt.user(commit, diff)
      Anthropic.judge(system, user, seed: run, model: model)
    end
  end

  defp to_record({:ok, judgment}, commit, run, model, version) do
    record = base(commit, run, model, version)

    extra = %{
      label: label_name(judgment.label),
      cia: judgment.cia,
      reason: judgment.reason,
      error: nil,
      usage: judgment.usage
    }

    Map.merge(record, extra)
  end

  defp to_record({:error, reason}, commit, run, model, version) do
    record = base(commit, run, model, version)
    extra = %{label: "ERROR", cia: nil, reason: nil, error: inspect(reason), usage: nil}
    Map.merge(record, extra)
  end

  defp base(commit, run, model, version) do
    now = DateTime.utc_now()

    %{
      hash: commit.hash,
      repo: commit.repo,
      run: run,
      model: model,
      prompt_version: version,
      judged_at: DateTime.to_iso8601(now)
    }
  end

  defp label_name(:vulnerable), do: "VULNERABLE"
  defp label_name(:neutral), do: "NEUTRAL"

  def unjudged(candidates, labels) do
    Enum.count(candidates, fn commit ->
      label = Map.fetch!(labels, commit.hash)
      length(label.votes) < length(@runs)
    end)
  end

  def labels(commits, records, model, version) do
    by_hash = Store.by_commit(records, model, version)

    Map.new(commits, fn commit ->
      if candidate?(commit) do
        votes = Map.get(by_hash, commit.hash, [])
        {commit.hash, %{votes: votes, final: Vote.majority(votes)}}
      else
        {commit.hash, %{votes: [], final: :neutral}}
      end
    end)
  end

  defp candidate?(%Commit{keyword_hit: keyword_hit, bot: bot}) do
    keyword_hit and not bot
  end
end
