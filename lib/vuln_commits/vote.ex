defmodule VulnCommits.Vote do
  def majority(labels), do: count(labels, 0, 0)

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

  def unanimous?([first | rest]), do: Enum.all?(rest, &(&1 == first))
  def unanimous?([]), do: false
end
