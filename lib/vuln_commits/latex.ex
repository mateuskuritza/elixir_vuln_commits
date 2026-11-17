defmodule VulnCommits.Latex do
  def table(headers, rows, caption, label) do
    cols = "l" <> String.duplicate("r", length(headers) - 1)

    row_lines = Enum.map(rows, fn row -> line(row) end)

    lines = [
      "\\begin{table}[htbp]",
      "\\centering",
      "\\caption{#{escape(caption)}}",
      "\\label{#{label}}",
      "\\begin{tabular}{#{cols}}",
      "\\toprule",
      line(headers),
      "\\midrule",
      row_lines,
      "\\bottomrule",
      "\\end{tabular}",
      "\\end{table}"
    ]

    flat_lines = List.flatten(lines)
    Enum.join(flat_lines, "\n") <> "\n"
  end

  defp line(cells) do
    cell_texts = Enum.map(cells, fn value -> cell(value) end)
    Enum.join(cell_texts, " & ") <> " \\\\"
  end

  defp cell(nil), do: "--"
  defp cell(value) when is_integer(value), do: Integer.to_string(value)
  defp cell(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp cell(value), do: escape(to_string(value))

  defp escape(text) do
    text = String.replace(text, "%", "\\%")
    text = String.replace(text, "_", "\\_")
    text = String.replace(text, "&", "\\&")
    text = String.replace(text, "#", "\\#")
    String.replace(text, "≥", "$\\geq$")
  end
end
