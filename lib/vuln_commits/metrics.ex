# contas de proporção usadas nas tabelas e no relatório.
defmodule VulnCommits.Metrics do
  # porcentagem de n em total, 2 casas. total zero vira 0.0 pra não dividir por zero.
  def proportion(_n, 0), do: 0.0
  def proportion(n, total), do: Float.round(100 * n / total, 2)
end
