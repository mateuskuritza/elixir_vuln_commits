defmodule VulnCommits.MetricsTest do
  use ExUnit.Case, async: true
  alias VulnCommits.Metrics

  test "proportion devolve porcentagem com 2 casas" do
    assert Metrics.proportion(1, 3) == 33.33
    assert Metrics.proportion(2, 4) == 50.0
  end

  test "proportion com total zero devolve 0.0" do
    assert Metrics.proportion(0, 0) == 0.0
  end

  test "confusion conta true_pos, false_pos, false_neg e true_neg" do
    pairs = [
      {:vulnerable, :vulnerable},
      {:neutral, :vulnerable},
      {:neutral, :neutral},
      {:vulnerable, :neutral}
    ]

    assert Metrics.confusion(pairs) == %{true_pos: 1, false_pos: 1, false_neg: 1, true_neg: 1}
  end

  test "confusion de lista vazia zera tudo" do
    assert Metrics.confusion([]) == %{true_pos: 0, false_pos: 0, false_neg: 0, true_neg: 0}
  end

  test "precision_recall_f1 com 1 de cada: tudo 0.5" do
    counts = %{true_pos: 1, false_pos: 1, false_neg: 1, true_neg: 1}
    assert Metrics.precision_recall_f1(counts) == %{precision: 0.5, recall: 0.5, f1: 0.5}
  end

  test "precision_recall_f1 com denominador zero devolve 0.0" do
    counts = %{true_pos: 0, false_pos: 0, false_neg: 0, true_neg: 3}
    assert Metrics.precision_recall_f1(counts) == %{precision: 0.0, recall: 0.0, f1: 0.0}
  end

  test "kappa do exemplo classico de Cohen (matriz [[20, 5], [10, 15]])" do
    pairs =
      duplicate({:vulnerable, :vulnerable}, 20) ++
        duplicate({:vulnerable, :neutral}, 5) ++
        duplicate({:neutral, :vulnerable}, 10) ++
        duplicate({:neutral, :neutral}, 15)

    assert_in_delta Metrics.cohen_kappa(pairs), 0.4, 0.001
  end

  test "kappa com concordancia perfeita e rotulos variados é 1.0" do
    pairs = [{:vulnerable, :vulnerable}, {:neutral, :neutral}, {:vulnerable, :vulnerable}]
    assert Metrics.cohen_kappa(pairs) == 1.0
  end

  test "kappa quando so existe um rotulo (pe == 1) devolve 1.0 se concordam" do
    pairs = [{:neutral, :neutral}, {:neutral, :neutral}]
    assert Metrics.cohen_kappa(pairs) == 1.0
  end

  test "kappa sem pares devolve 0.0" do
    assert Metrics.cohen_kappa([]) == 0.0
  end

  test "pairwise_kappa devolve media, minimo e os 3 pares (1-2, 1-3, 2-3)" do
    run1 =
      duplicate(:vulnerable, 20) ++
        duplicate(:vulnerable, 5) ++ duplicate(:neutral, 10) ++ duplicate(:neutral, 15)

    run2 =
      duplicate(:vulnerable, 20) ++
        duplicate(:neutral, 5) ++ duplicate(:vulnerable, 10) ++ duplicate(:neutral, 15)

    run3 = run1

    result = Metrics.pairwise_kappa([run1, run2, run3])

    assert [k12, k13, k23] = result.pairs
    assert_in_delta k12, 0.4, 0.001
    assert_in_delta k13, 1.0, 0.001
    assert_in_delta k23, 0.4, 0.001
    assert_in_delta result.mean, 0.6, 0.001
    assert_in_delta result.min, 0.4, 0.001
  end

  defp duplicate(value, n), do: List.duplicate(value, n)
end
