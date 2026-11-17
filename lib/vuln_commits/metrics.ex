defmodule VulnCommits.Metrics do
  def proportion(_n, 0), do: 0.0
  def proportion(n, total), do: Float.round(100 * n / total, 2)

  defp ratio(_a, b) when b == 0, do: 0.0
  defp ratio(a, b), do: a / b

  def confusion(pairs), do: count(pairs, %{true_pos: 0, false_pos: 0, false_neg: 0, true_neg: 0})

  defp count([], acc), do: acc
  defp count([{truth, pred} | rest], acc), do: count(rest, bump(acc, truth, pred))

  defp bump(acc, :vulnerable, :vulnerable), do: %{acc | true_pos: acc.true_pos + 1}
  defp bump(acc, :neutral, :vulnerable), do: %{acc | false_pos: acc.false_pos + 1}
  defp bump(acc, :vulnerable, :neutral), do: %{acc | false_neg: acc.false_neg + 1}
  defp bump(acc, :neutral, :neutral), do: %{acc | true_neg: acc.true_neg + 1}

  def precision_recall_f1(%{true_pos: tp, false_pos: fp, false_neg: fneg}) do
    precision = ratio(tp, tp + fp)
    recall = ratio(tp, tp + fneg)
    f1 = ratio(2 * precision * recall, precision + recall)
    %{precision: precision, recall: recall, f1: f1}
  end

  def cohen_kappa([]), do: 0.0

  def cohen_kappa(pairs) do
    n = length(pairs)
    {as, bs} = Enum.unzip(pairs)
    freq_a = Enum.frequencies(as)
    freq_b = Enum.frequencies(bs)

    po = ratio(Enum.count(pairs, fn {a, b} -> a == b end), n)

    pe =
      freq_a
      |> Enum.map(fn {label, count_a} ->
        ratio(count_a, n) * ratio(Map.get(freq_b, label, 0), n)
      end)
      |> Enum.sum()

    cond do
      pe != 1 -> (po - pe) / (1 - pe)
      po == 1 -> 1.0
      true -> 0.0
    end
  end

  def pairwise_kappa(runs) do
    kappas =
      for {run_a, i} <- Enum.with_index(runs),
          {run_b, j} <- Enum.with_index(runs),
          i < j,
          do: cohen_kappa(Enum.zip(run_a, run_b))

    %{mean: Enum.sum(kappas) / length(kappas), min: Enum.min(kappas), pairs: kappas}
  end
end
