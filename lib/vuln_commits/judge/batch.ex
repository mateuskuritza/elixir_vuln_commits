defmodule VulnCommits.Judge.Batch do
  alias VulnCommits.Judge.{Prompt, Store}

  @labels %{"VULNERABLE" => "VULNERABLE", "NEUTRAL" => "NEUTRAL"}
  @cias ~w(confidentiality integrity availability none)

  def model, do: System.get_env("JUDGE_MODEL", "claude-opus-5-5")

  def export(commits, out_dir, opts) do
    size = Keyword.get(opts, :batch_size, 20)
    version = Keyword.fetch!(opts, :version)
    diff_fun = Keyword.fetch!(opts, :diff_fun)
    File.mkdir_p!(out_dir)

    commits
    |> Enum.chunk_every(size)
    |> Enum.with_index(1)
    |> Enum.map(fn {chunk, i} ->
      path = Path.join(out_dir, "batch-#{String.pad_leading("#{i}", 3, "0")}.md")
      File.write!(path, batch_text(chunk, version, diff_fun))
      %{path: path, hashes: Enum.map(chunk, & &1.hash)}
    end)
  end

  defp batch_text(commits, version, diff_fun) do
    blocks =
      Enum.map_join(commits, "\n\n", fn c ->
        "=== COMMIT #{c.hash} ===\n" <> Prompt.user(c, diff_fun.(c))
      end)

    """
    # Lote de julgamento (#{length(commits)} commits)

    Julgue cada commit abaixo de forma independente, seguindo exatamente as instruções do sistema.
    Responda com uma linha JSON por commit, na ordem, no formato:
    {"hash": "<hash>", "label": "VULNERABLE" | "NEUTRAL", "cia": "confidentiality" | "integrity" | "availability" | "none", "reason": "<uma ou duas frases>"}

    ## Instruções do sistema

    #{Prompt.system(version)}

    ## Commits

    #{blocks}
    """
  end

  def parse(text, expected) do
    parsed =
      text
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&String.starts_with?(&1, "{"))
      |> Enum.map(&decode/1)

    bad = Enum.filter(parsed, &match?({:error, _}, &1))
    good = for {:ok, j} <- parsed, j["hash"] in expected, into: %{}, do: {j["hash"], j}
    missing = Enum.reject(expected, &Map.has_key?(good, &1))

    case {bad, missing} do
      {[], []} -> {:ok, Enum.map(expected, &Map.fetch!(good, &1))}
      _ -> {:error, %{invalid: length(bad), missing: missing}}
    end
  end

  defp decode(line) do
    with {:ok, %{"hash" => h, "label" => l, "cia" => c} = j} when is_binary(h) <-
           Jason.decode(line),
         {:ok, _} <- Map.fetch(@labels, l),
         true <- c in @cias do
      {:ok, j}
    else
      _ -> {:error, line}
    end
  end

  def store(judgments, commits_by_hash, path, opts) do
    run = Keyword.fetch!(opts, :run)
    model = Keyword.fetch!(opts, :model)
    version = Keyword.fetch!(opts, :version)
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    Enum.each(judgments, fn j ->
      Store.append(path, %{
        hash: j["hash"],
        repo: Map.fetch!(commits_by_hash, j["hash"]).repo,
        run: run,
        model: model,
        prompt_version: version,
        label: j["label"],
        cia: j["cia"],
        reason: j["reason"],
        error: nil,
        usage: nil,
        judged_at: now
      })
    end)
  end
end
