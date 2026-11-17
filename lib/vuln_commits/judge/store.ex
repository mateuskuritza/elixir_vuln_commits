defmodule VulnCommits.Judge.Store do
  def append(path, record) do
    File.mkdir_p!(Path.dirname(path))
    line = Jason.encode!(record) <> "\n"
    File.write!(path, line, [:append])
    :ok
  end

  def load(path) do
    if File.exists?(path) do
      path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.map(&Jason.decode!(&1, keys: :atoms))
    else
      []
    end
  end

  def done(records) do
    for %{label: label} = r <- records, label != "ERROR", into: MapSet.new() do
      {r.hash, r.run, r.model, r.prompt_version}
    end
  end

  def by_commit(records, model, prompt_version) do
    records
    |> Enum.filter(&(&1.model == model and &1.prompt_version == prompt_version))
    |> Enum.reject(&(&1.label == "ERROR"))
    |> Enum.reduce(%{}, fn r, acc -> Map.put(acc, {r.hash, r.run}, label_atom(r.label)) end)
    |> Enum.sort_by(fn {{hash, run}, _label} -> {hash, run} end)
    |> Enum.group_by(fn {{hash, _run}, _label} -> hash end, fn {_key, label} -> label end)
  end

  defp label_atom("VULNERABLE"), do: :vulnerable
  defp label_atom("NEUTRAL"), do: :neutral
end
