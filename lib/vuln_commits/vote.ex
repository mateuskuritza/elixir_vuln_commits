# voto por maioria dos 3 runs do estágio 2
defmodule VulnCommits.Vote do
  # 2 votos válidos iguais decidem. erro não conta pra nenhum lado.
  def majority(labels), do: count(labels, 0, 0)

  # conta vulnerable e neutral andando pela lista (cabeça e cauda)
  defp count([], vulnerable, neutral) do
    cond do
      vulnerable >= 2 -> :vulnerable
      neutral >= 2 -> :neutral
      true -> :undecided
    end
  end

  defp count([:vulnerable | rest], vulnerable, neutral), do: count(rest, vulnerable + 1, neutral)
  defp count([:neutral | rest], vulnerable, neutral), do: count(rest, vulnerable, neutral + 1)
  defp count([_error | rest], vulnerable, neutral), do: count(rest, vulnerable, neutral)

  # todos os rótulos iguais (lista vazia não conta)
  def unanimous?([first | rest]), do: Enum.all?(rest, &(&1 == first))
  def unanimous?([]), do: false
end
