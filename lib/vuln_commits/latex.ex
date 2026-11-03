# monta tabelas em latex (booktabs) a partir de cabeçalhos e linhas
defmodule VulnCommits.Latex do
  # headers: lista de textos. rows: lista de listas (números, textos ou nil).
  # o resultado já vem com \begin{table}, pra dar \input direto no artigo.
  def table(headers, rows, caption, label) do
    cols = "l" <> String.duplicate("r", length(headers) - 1)

    [
      "\\begin{table}[htbp]",
      "\\centering",
      "\\caption{#{escape(caption)}}",
      "\\label{#{label}}",
      "\\begin{tabular}{#{cols}}",
      "\\toprule",
      line(headers),
      "\\midrule",
      Enum.map(rows, &line/1),
      "\\bottomrule",
      "\\end{tabular}",
      "\\end{table}"
    ]
    |> List.flatten()
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp line(cells), do: Enum.map_join(cells, " & ", &cell/1) <> " \\\\"

  # inteiro fica inteiro, float com duas casas e ponto, nil vira traço
  defp cell(nil), do: "--"
  defp cell(value) when is_integer(value), do: Integer.to_string(value)
  defp cell(value) when is_float(value), do: :erlang.float_to_binary(value, decimals: 2)
  defp cell(value), do: value |> to_string() |> escape()

  # caracteres que o latex trata como comando
  defp escape(text) do
    text
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
    |> String.replace("&", "\\&")
    |> String.replace("#", "\\#")
    |> String.replace("≥", "$\\geq$")
  end
end
