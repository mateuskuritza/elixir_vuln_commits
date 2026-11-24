defmodule VulnCommits.Population do
  alias VulnCommits.Metrics

  # faixas de tamanho da mensagem, em palavras
  @bins [{0, 5}, {6, 10}, {11, 20}, {21, 50}, {51, :inf}]

  def bins, do: @bins

  defp vulnerable?(labels, commit) do
    case Map.fetch(labels, commit.hash) do
      {:ok, %{final: :vulnerable}} -> true
      _other -> false
    end
  end

  def count(commits, labels),
    do: Enum.count(commits, fn commit -> vulnerable?(labels, commit) end)

  def row(name, commits, labels) do
    vulnerable = count(commits, labels)

    %{
      name: name,
      commits: length(commits),
      vulnerable: vulnerable,
      pct: Metrics.proportion(vulnerable, length(commits))
    }
  end

  # compara dois recortes: taxa de cada um e p do teste exato de fisher
  def compare(name, a, b, labels) do
    left = row(name, a, labels)
    right = row(name, b, labels)
    p = fisher(left.vulnerable, left.commits, right.vulnerable, right.commits)
    %{name: name, left: left, right: right, p: p}
  end

  def words(commit), do: length(String.split(commit.message || ""))

  def in_bin?(commit, {low, :inf}), do: words(commit) >= low
  def in_bin?(commit, {low, high}), do: words(commit) >= low and words(commit) <= high

  def by_length(commits, labels) do
    Enum.map(@bins, fn bin ->
      group = Enum.filter(commits, fn commit -> in_bin?(commit, bin) end)
      candidates = Enum.count(group, fn commit -> commit.keyword_hit and not commit.bot end)

      %{
        bin: bin,
        commits: length(group),
        candidates: Metrics.proportion(candidates, length(group)),
        vulnerable: Metrics.proportion(count(group, labels), length(group))
      }
    end)
  end

  # taxa de `commits` reponderada pela distribuição de tamanho de mensagem de `reference`
  def standardized(commits, reference, labels) do
    total = length(reference)

    sum =
      Enum.reduce(@bins, 0.0, fn bin, acc ->
        weight = Enum.count(reference, fn commit -> in_bin?(commit, bin) end) / total
        group = Enum.filter(commits, fn commit -> in_bin?(commit, bin) end)
        rate = if group == [], do: 0.0, else: count(group, labels) / length(group)
        acc + weight * rate
      end)

    Float.round(100 * sum, 2)
  end

  # fisher bilateral: soma as tabelas com probabilidade <= a observada
  def fisher(a, n1, b, n2) do
    total = n1 + n2
    hits = a + b
    logf = log_factorials(total)
    prob = fn x -> exp_prob(x, n1, n2, hits, total, logf) end
    observed = prob.(a)
    low = max(0, hits - n2)
    high = min(hits, n1)

    low..high
    |> Enum.map(prob)
    |> Enum.filter(fn p -> p <= observed * (1 + 1.0e-7) end)
    |> Enum.sum()
    |> min(1.0)
  end

  defp exp_prob(x, n1, n2, hits, total, logf) do
    log_p =
      elem(logf, n1) + elem(logf, n2) + elem(logf, hits) + elem(logf, total - hits) -
        elem(logf, total) - elem(logf, x) - elem(logf, n1 - x) - elem(logf, hits - x) -
        elem(logf, n2 - hits + x)

    :math.exp(log_p)
  end

  defp log_factorials(n) do
    values = Enum.scan(1..n, 0.0, fn k, acc -> acc + :math.log(k) end)
    List.to_tuple([0.0 | values])
  end
end
