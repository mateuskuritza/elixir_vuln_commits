# struct de um commit. os campos são preenchidos aos poucos pelos estágios.
defmodule VulnCommits.Commit do
  defstruct repo: nil,
            hash: nil,
            date: nil,
            year: nil,
            author_name: nil,
            author_email: nil,
            message: nil,
            files: [],
            elixir_files: [],
            merge?: false,
            keyword_hit: false,
            keywords: [],
            bot: false,
            ai_markers: [],
            human_label: nil,
            period: nil

  # uma cláusula por extensão aceita. "bin/iex" sem extensão cai na última.
  def elixir_file?(path) do
    elixir_extension?(Path.extname(path))
  end

  defp elixir_extension?(".ex"), do: true
  defp elixir_extension?(".exs"), do: true
  defp elixir_extension?(".eex"), do: true
  defp elixir_extension?(".heex"), do: true
  defp elixir_extension?(".leex"), do: true
  defp elixir_extension?(_), do: false

  # ano sai da data do commit.
  def year_of(%__MODULE__{date: date}), do: date.year
end
