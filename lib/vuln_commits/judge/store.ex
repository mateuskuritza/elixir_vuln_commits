defmodule VulnCommits.Judge.Store do
  def append(path, record) do
    File.mkdir_p!(Path.dirname(path))
    line = Jason.encode!(record) <> "\n"
    File.write!(path, line, [:append])
    :ok
  end

  def load(path) do
    if File.exists?(path) do
      content = File.read!(path)
      lines = String.split(content, "\n")
      trimmed = Enum.map(lines, fn line -> String.trim(line) end)
      not_empty = Enum.filter(trimmed, fn line -> line != "" end)
      Enum.map(not_empty, fn line -> Jason.decode!(line, keys: :atoms) end)
    else
      []
    end
  end

  def done(records) do
    valid = Enum.filter(records, fn record -> record.label != "ERROR" end)

    keys =
      Enum.map(valid, fn record ->
        {record.hash, record.run, record.model, record.prompt_version}
      end)

    MapSet.new(keys)
  end

  def by_commit(records, model, prompt_version) do
    same_setup =
      Enum.filter(records, fn record ->
        record.model == model and record.prompt_version == prompt_version
      end)

    valid = Enum.filter(same_setup, fn record -> record.label != "ERROR" end)

    latest_by_key =
      Map.new(valid, fn record ->
        {{record.hash, record.run}, label_atom(record.label)}
      end)

    sorted = Enum.sort_by(latest_by_key, fn {{hash, run}, _label} -> {hash, run} end)

    Enum.group_by(
      sorted,
      fn {{hash, _run}, _label} -> hash end,
      fn {_key, label} -> label end
    )
  end

  defp label_atom("VULNERABLE"), do: :vulnerable
  defp label_atom("NEUTRAL"), do: :neutral
end
