defmodule VulnCommits.CSV do
  alias NimbleCSV.RFC4180, as: Parser
  alias VulnCommits.Text

  def read(path) do
    content = File.stream!(path)
    parsed_rows = Parser.parse_stream(content, skip_headers: false)
    clean_rows = Enum.map(parsed_rows, fn row -> clean_row(row) end)
    [header | rows] = clean_rows

    Enum.map(rows, fn row -> row_to_map(header, row) end)
  end

  defp clean_row(row) do
    Enum.map(row, fn cell -> Text.scrub(cell) end)
  end

  defp row_to_map(header, row) do
    pairs = Enum.zip(header, row)
    Map.new(pairs)
  end

  def write(path, headers, rows) do
    folder = Path.dirname(path)
    File.mkdir_p!(folder)
    content = Parser.dump_to_iodata([headers | rows])
    File.write!(path, content)
  end
end
