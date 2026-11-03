# orquestracao do estagio 2: escolhe os candidatos, roda o juiz e junta os votos
defmodule VulnCommits.Judge do
  alias VulnCommits.{Commit, Vote}
  alias VulnCommits.Judge.{OpenAI, Prompt, Store}

  @runs [1, 2, 3]
  @max_concurrency 4
  @progress_every 50

  # candidatos: keyword_hit, sem bot, do periodo e (se dado) dentro do intervalo de anos
  def candidates(commits, period, opts) do
    years = Keyword.get(opts, :years)

    Enum.filter(commits, fn c ->
      c.keyword_hit and not c.bot and c.period == period and in_years?(c.year, years)
    end)
  end

  defp in_years?(_year, nil), do: true
  defp in_years?(year, range), do: year in range

  # pares {commit, run} que ainda não têm registro bem sucedido
  def pending(candidates, done_set, model, version) do
    for c <- candidates,
        run <- @runs,
        not MapSet.member?(done_set, {c.hash, run, model, version}),
        do: {c, run}
  end

  # roda o juiz em paralelo e grava cada resultado no jsonl a partir deste processo.
  # opts: dirs (%{repo => dir}), path, model, version e judge_fun (injetável nos testes)
  def run(pairs, opts) do
    model = Keyword.get_lazy(opts, :model, &OpenAI.model/0)
    version = Keyword.get_lazy(opts, :version, &Prompt.version/0)
    dirs = Keyword.fetch!(opts, :dirs)
    path = Keyword.fetch!(opts, :path)
    judge_fun = Keyword.get_lazy(opts, :judge_fun, fn -> default_judge(model, version) end)
    total = length(pairs)

    pairs
    |> Task.async_stream(
      fn {commit, run} ->
        judge_fun.(commit, Map.get(dirs, commit.repo), run)
        |> to_record(commit, run, model, version)
      end,
      max_concurrency: @max_concurrency,
      timeout: :infinity
    )
    |> Enum.with_index(1)
    |> Enum.each(fn {{:ok, record}, i} ->
      Store.append(path, record)
      if rem(i, @progress_every) == 0, do: IO.puts("julgados #{i} de #{total}")
    end)

    IO.puts("julgados #{total} de #{total}")
    :ok
  end

  # juiz padrão: monta o prompt do estágio 2 e chama a openai com a seed do run
  defp default_judge(model, version) do
    system = Prompt.system(version)

    fn commit, dir, run ->
      diff = Prompt.diff_for(commit, dir)
      user = Prompt.user(commit, diff)
      OpenAI.judge(system, user, seed: run, model: model)
    end
  end

  # uma linha do jsonl; erro do juiz vira ERROR e não derruba a execução
  defp to_record({:ok, judgment}, commit, run, model, version) do
    base(commit, run, model, version)
    |> Map.merge(%{
      label: label_name(judgment.label),
      cia: judgment.cia,
      reason: judgment.reason,
      error: nil,
      usage: judgment.usage
    })
  end

  defp to_record({:error, reason}, commit, run, model, version) do
    base(commit, run, model, version)
    |> Map.merge(%{label: "ERROR", cia: nil, reason: nil, error: inspect(reason), usage: nil})
  end

  defp base(commit, run, model, version) do
    %{
      hash: commit.hash,
      repo: commit.repo,
      run: run,
      model: model,
      prompt_version: version,
      judged_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp label_name(:vulnerable), do: "VULNERABLE"
  defp label_name(:neutral), do: "NEUTRAL"

  # rótulo final de cada commit: não candidato é neutral; candidato usa a maioria dos registros
  def labels(commits, records, model, version) do
    by_hash = Store.by_commit(records, model, version)

    Map.new(commits, fn c ->
      if candidate?(c) do
        votes = Map.get(by_hash, c.hash, [])
        {c.hash, %{votes: votes, final: Vote.majority(votes)}}
      else
        {c.hash, %{votes: [], final: :neutral}}
      end
    end)
  end

  defp candidate?(%Commit{keyword_hit: keyword_hit, bot: bot}), do: keyword_hit and not bot
end
