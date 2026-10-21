# leitura e escrita de csv. o cabeçalho vira as chaves (string) de cada linha.
defmodule VulnCommits.CSV do
  alias NimbleCSV.RFC4180, as: Parser
  alias VulnCommits.Text

  # devolve uma lista de maps, um por linha de dados
  def read(path) do
    [header | rows] =
      path
      |> File.stream!()
      |> Parser.parse_stream(skip_headers: false)
      |> Enum.map(fn row -> Enum.map(row, &Text.scrub/1) end)

    Enum.map(rows, fn row -> header |> Enum.zip(row) |> Map.new() end)
  end

  # headers: lista de nomes. rows: lista de listas na mesma ordem
  def write(path, headers, rows) do
    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(path, Parser.dump_to_iodata([headers | rows]))
  end
end
