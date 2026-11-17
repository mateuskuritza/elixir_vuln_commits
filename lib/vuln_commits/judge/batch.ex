defmodule VulnCommits.Judge.Batch do
  alias VulnCommits.Judge.Prompt
  alias VulnCommits.Judge.Store

  @labels ["VULNERABLE", "NEUTRAL"]
  @cias ["confidentiality", "integrity", "availability", "none"]

  def model, do: System.get_env("JUDGE_MODEL", "claude-opus-5-5")

  def export(commits, out_dir, opts) do
    size = Keyword.get(opts, :batch_size, 20)
    version = Keyword.fetch!(opts, :version)
    diff_fun = Keyword.fetch!(opts, :diff_fun)
    File.mkdir_p!(out_dir)

    chunks = Enum.chunk_every(commits, size)
    numbered_chunks = Enum.with_index(chunks, 1)

    Enum.map(numbered_chunks, fn {chunk, number} ->
      number_text = String.pad_leading("#{number}", 3, "0")
      path = Path.join(out_dir, "batch-#{number_text}.md")
      File.write!(path, batch_text(chunk, version, diff_fun))
      hashes = Enum.map(chunk, fn commit -> commit.hash end)
      %{path: path, hashes: hashes}
    end)
  end

  defp batch_text(commits, version, diff_fun) do
    commit_texts =
      Enum.map(commits, fn commit ->
        diff = diff_fun.(commit)
        "=== COMMIT #{commit.hash} ===\n" <> Prompt.user(commit, diff)
      end)

    blocks = Enum.join(commit_texts, "\n\n")

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
    lines = String.split(text, "\n")
    trimmed = Enum.map(lines, fn line -> String.trim(line) end)
    json_lines = Enum.filter(trimmed, fn line -> String.starts_with?(line, "{") end)
    parsed = Enum.map(json_lines, fn line -> decode(line) end)

    bad = Enum.filter(parsed, fn result -> error?(result) end)

    good_judgments =
      parsed
      |> Enum.filter(fn result -> not error?(result) end)
      |> Enum.map(fn {:ok, judgment} -> judgment end)

    expected_judgments =
      Enum.filter(good_judgments, fn judgment -> judgment["hash"] in expected end)

    good = Map.new(expected_judgments, fn judgment -> {judgment["hash"], judgment} end)
    missing = Enum.filter(expected, fn hash -> not Map.has_key?(good, hash) end)

    if bad == [] and missing == [] do
      ordered = Enum.map(expected, fn hash -> Map.fetch!(good, hash) end)
      {:ok, ordered}
    else
      {:error, %{invalid: length(bad), missing: missing}}
    end
  end

  defp error?({:error, _line}), do: true
  defp error?({:ok, _judgment}), do: false

  defp decode(line) do
    case Jason.decode(line) do
      {:ok, %{"hash" => hash, "label" => label, "cia" => cia} = judgment} ->
        if is_binary(hash) and label in @labels and cia in @cias do
          {:ok, judgment}
        else
          {:error, line}
        end

      _other ->
        {:error, line}
    end
  end

  def store(judgments, commits_by_hash, path, opts) do
    run = Keyword.fetch!(opts, :run)
    model = Keyword.fetch!(opts, :model)
    version = Keyword.fetch!(opts, :version)
    now = DateTime.to_iso8601(DateTime.utc_now())

    Enum.each(judgments, fn judgment ->
      commit = Map.fetch!(commits_by_hash, judgment["hash"])

      Store.append(path, %{
        hash: judgment["hash"],
        repo: commit.repo,
        run: run,
        model: model,
        prompt_version: version,
        label: judgment["label"],
        cia: judgment["cia"],
        reason: judgment["reason"],
        error: nil,
        usage: nil,
        judged_at: now
      })
    end)
  end
end
