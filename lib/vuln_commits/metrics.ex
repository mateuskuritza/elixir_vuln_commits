defmodule VulnCommits.Metrics do
  def proportion(_n, 0), do: 0.0
  def proportion(n, total), do: Float.round(100 * n / total, 2)

  defp ratio(a, b) do
    if b == 0 do
      0.0
    else
      a / b
    end
  end

  def confusion(pairs) do
    empty = %{true_pos: 0, false_pos: 0, false_neg: 0, true_neg: 0}
    count(pairs, empty)
  end

  defp count([], counts), do: counts

  defp count([{truth, prediction} | rest], counts) do
    new_counts = bump(counts, truth, prediction)
    count(rest, new_counts)
  end

  defp bump(counts, :vulnerable, :vulnerable), do: %{counts | true_pos: counts.true_pos + 1}
  defp bump(counts, :neutral, :vulnerable), do: %{counts | false_pos: counts.false_pos + 1}
  defp bump(counts, :vulnerable, :neutral), do: %{counts | false_neg: counts.false_neg + 1}
  defp bump(counts, :neutral, :neutral), do: %{counts | true_neg: counts.true_neg + 1}

  def precision_recall_f1(%{true_pos: true_pos, false_pos: false_pos, false_neg: false_neg}) do
    precision = ratio(true_pos, true_pos + false_pos)
    recall = ratio(true_pos, true_pos + false_neg)
    f1 = ratio(2 * precision * recall, precision + recall)
    %{precision: precision, recall: recall, f1: f1}
  end

  def cohen_kappa([]), do: 0.0

  def cohen_kappa(pairs) do
    total = length(pairs)
    labels_a = Enum.map(pairs, fn {label_a, _label_b} -> label_a end)
    labels_b = Enum.map(pairs, fn {_label_a, label_b} -> label_b end)
    frequencies_a = Enum.frequencies(labels_a)
    frequencies_b = Enum.frequencies(labels_b)

    agreements = Enum.count(pairs, fn {label_a, label_b} -> label_a == label_b end)
    observed = ratio(agreements, total)

    chance_terms =
      Enum.map(frequencies_a, fn {label, count_a} ->
        count_b = Map.get(frequencies_b, label, 0)
        ratio(count_a, total) * ratio(count_b, total)
      end)

    expected = Enum.sum(chance_terms)

    if expected != 1 do
      (observed - expected) / (1 - expected)
    else
      if observed == 1 do
        1.0
      else
        0.0
      end
    end
  end

  def pairwise_kappa(runs) do
    run_pairs = all_pairs(runs)

    kappas =
      Enum.map(run_pairs, fn {run_a, run_b} ->
        cohen_kappa(Enum.zip(run_a, run_b))
      end)

    %{mean: Enum.sum(kappas) / length(kappas), min: Enum.min(kappas), pairs: kappas}
  end

  defp all_pairs([]), do: []

  defp all_pairs([first | rest]) do
    pairs_with_first = Enum.map(rest, fn other -> {first, other} end)
    pairs_with_first ++ all_pairs(rest)
  end
end
