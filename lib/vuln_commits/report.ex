defmodule VulnCommits.Report do
  alias VulnCommits.Metrics
  alias VulnCommits.Vote

  @paper_table3 %{
    2012 => 0.94,
    2013 => 0.48,
    2014 => 1.74,
    2015 => 3.38,
    2016 => 1.92,
    2017 => 1.22,
    2018 => 1.05,
    2019 => 3.45,
    2020 => 3.85
  }

  @paper_totals %{
    commits: 4446,
    vulnerable: 90,
    proportion: 2.0,
    files: 1769,
    files_in_vulnerable: 319,
    repos: 25,
    repos_with_vulnerable: 9
  }

  def paper_table3, do: @paper_table3
  def paper_totals, do: @paper_totals

  defp ours(labels, commit) do
    label = Map.fetch!(labels, commit.hash)
    final(label.final)
  end

  defp final(:undecided), do: :neutral
  defp final(label), do: label

  defp human_labels(commits) do
    Map.new(commits, fn commit ->
      {commit.hash, %{votes: [], final: commit.human_label}}
    end)
  end

  defp vulnerable(commits, labels) do
    Enum.filter(commits, fn commit -> ours(labels, commit) == :vulnerable end)
  end

  def match(original, labels) do
    human = human_labels(original)
    human_stats = stats(original, human)
    our_stats = stats(original, labels)

    metrics = [
      {"commits", :commits},
      {"vulneráveis", :vulnerable},
      {"proporção (%)", :proportion},
      {"repositórios", :repos},
      {"repositórios com ≥1 vulnerável", :repos_with_vulnerable},
      {"arquivos", :files},
      {"arquivos em vulneráveis", :files_in_vulnerable},
      {"arquivos em vulneráveis (%)", :files_pct}
    ]

    Enum.map(metrics, fn {name, key} ->
      %{
        metric: name,
        paper: paper_value(key),
        human_active: human_stats[key],
        ours: our_stats[key]
      }
    end)
  end

  defp paper_value(:files_pct) do
    Metrics.proportion(@paper_totals.files_in_vulnerable, @paper_totals.files)
  end

  defp paper_value(key), do: Map.fetch!(@paper_totals, key)

  defp stats(commits, labels) do
    vulnerable_commits = vulnerable(commits, labels)

    %{
      commits: length(commits),
      vulnerable: length(vulnerable_commits),
      proportion: Metrics.proportion(length(vulnerable_commits), length(commits)),
      repos: count_repos(commits),
      repos_with_vulnerable: count_repos(vulnerable_commits),
      files: count_files(commits),
      files_in_vulnerable: count_files(vulnerable_commits),
      files_pct: files_pct(commits, labels)
    }
  end

  defp count_repos(commits) do
    repos = Enum.map(commits, fn commit -> commit.repo end)
    length(Enum.uniq(repos))
  end

  defp count_files(commits) do
    files =
      Enum.flat_map(commits, fn commit ->
        Enum.map(commit.elixir_files, fn file -> {commit.repo, file} end)
      end)

    length(Enum.uniq(files))
  end

  def files_pct(commits, labels) do
    vulnerable_commits = vulnerable(commits, labels)
    Metrics.proportion(count_files(vulnerable_commits), count_files(commits))
  end

  def per_year(original, extended, labels) do
    human = human_labels(original)
    by_year = Enum.group_by(original, fn commit -> commit.year end)
    not_bots = Enum.reject(extended, fn commit -> commit.bot end)
    extended_by_year = Enum.group_by(not_bots, fn commit -> commit.year end)

    years = Enum.to_list(2012..2025)

    Enum.map(years, fn year ->
      if year <= 2020 do
        group = Map.get(by_year, year, [])

        %{
          year: year,
          commits: length(group),
          paper: Map.get(@paper_table3, year),
          human_active: share(group, human),
          ours: share(group, labels)
        }
      else
        group = Map.get(extended_by_year, year, [])

        %{
          year: year,
          commits: length(group),
          paper: nil,
          human_active: nil,
          ours: share(group, labels)
        }
      end
    end)
  end

  defp share(commits, labels) do
    vulnerable_commits = vulnerable(commits, labels)
    Metrics.proportion(length(vulnerable_commits), length(commits))
  end

  def agreement(original, labels, extended, opts \\ []) do
    eval_years = Keyword.get(opts, :years_eval, 2017..2020)
    dev_years = Keyword.get(opts, :years_dev, 2012..2016)

    %{
      eval: scores(original, labels, eval_years),
      dev: scores(original, labels, dev_years),
      all: scores(original, labels, 2012..2020),
      runs: runs(original ++ extended, labels)
    }
  end

  defp scores(original, labels, years) do
    in_years = Enum.filter(original, fn commit -> commit.year in years end)

    pairs =
      Enum.map(in_years, fn commit ->
        {commit.human_label, ours(labels, commit)}
      end)

    confusion = Metrics.confusion(pairs)
    result = %{n: length(pairs), confusion: confusion, kappa: Metrics.cohen_kappa(pairs)}
    Map.merge(result, Metrics.precision_recall_f1(confusion))
  end

  defp runs(commits, labels) do
    finals = Enum.map(commits, fn commit -> Map.fetch!(labels, commit.hash) end)
    with_three_votes = Enum.filter(finals, fn label -> length(label.votes) == 3 end)
    triples = Enum.map(with_three_votes, fn label -> label.votes end)
    undecided = Enum.count(finals, fn label -> label.final == :undecided end)

    if triples == [] do
      %{n: 0, mean_kappa: nil, min_kappa: nil, unanimous_pct: nil, undecided: undecided}
    else
      first_run = Enum.map(triples, fn [vote, _, _] -> vote end)
      second_run = Enum.map(triples, fn [_, vote, _] -> vote end)
      third_run = Enum.map(triples, fn [_, _, vote] -> vote end)
      kappa = Metrics.pairwise_kappa([first_run, second_run, third_run])

      unanimous = Enum.count(triples, fn votes -> Vote.unanimous?(votes) end)

      %{
        n: length(triples),
        mean_kappa: kappa.mean,
        min_kappa: kappa.min,
        unanimous_pct: Metrics.proportion(unanimous, length(triples)),
        undecided: undecided
      }
    end
  end

  def vulnerable_density(commits, labels, lines, years \\ 2021..2025) do
    not_bots = Enum.reject(commits, fn commit -> commit.bot end)
    by_year = Enum.group_by(not_bots, fn commit -> commit.year end)

    Enum.map(Enum.to_list(years), fn year ->
      density(to_string(year), Map.get(by_year, year, []), labels, lines)
      |> Map.put(:year, year)
    end)
  end

  # o mesmo cálculo para um período inteiro (2012 a 2020 e 2021 a 2025)
  def vulnerable_density_periods(commits, labels, lines, periods) do
    not_bots = Enum.reject(commits, fn commit -> commit.bot end)

    Enum.map(periods, fn first..last//_ ->
      group = Enum.filter(not_bots, fn commit -> commit.year in first..last end)
      density("#{first} a #{last}", group, labels, lines)
    end)
  end

  defp density(name, group, labels, lines) do
    added = Enum.sum(Enum.map(group, fn commit -> Map.fetch!(lines, commit.hash).added end))
    vulnerable_count = length(vulnerable(group, labels))

    %{
      name: name,
      vulnerable: vulnerable_count,
      added: added,
      per_10k_lines: per_10k(vulnerable_count, added)
    }
  end

  defp per_10k(_count, 0), do: 0.0
  defp per_10k(count, added), do: Float.round(10_000 * count / added, 2)

  def vulnerable_by_size(extended, labels) do
    not_bots = Enum.reject(extended, fn commit -> commit.bot end)
    by_band = Enum.group_by(not_bots, fn commit -> size_band(length(commit.elixir_files)) end)

    Enum.map(["1", "2 a 4", "5 a 9", "10 ou mais"], fn band ->
      group = Map.get(by_band, band, [])
      vulnerable_count = length(vulnerable(group, labels))

      %{
        band: band,
        commits: length(group),
        vulnerable: vulnerable_count,
        proportion: Metrics.proportion(vulnerable_count, length(group))
      }
    end)
  end

  defp size_band(1), do: "1"
  defp size_band(count) when count < 5, do: "2 a 4"
  defp size_band(count) when count < 10, do: "5 a 9"
  defp size_band(_count), do: "10 ou mais"

  def bots(extended) do
    by_year = Enum.group_by(extended, fn commit -> commit.year end)
    years = Enum.to_list(2021..2025)

    Enum.map(years, fn year ->
      group = Map.get(by_year, year, [])
      bot_count = Enum.count(group, fn commit -> commit.bot end)
      %{year: year, bots: bot_count, total: length(group)}
    end)
  end

  def ai(extended, labels, repo_markers) do
    not_bots = Enum.reject(extended, fn commit -> commit.bot end)
    by_year = Enum.group_by(not_bots, fn commit -> commit.year end)
    years = Enum.to_list(2021..2025)

    per_year =
      Enum.map(years, fn year ->
        group = Map.get(by_year, year, [])
        with_marker = Enum.filter(group, fn commit -> commit.ai_markers != [] end)
        without_marker = Enum.filter(group, fn commit -> commit.ai_markers == [] end)

        %{
          year: year,
          with_marker: length(with_marker),
          vulnerable_with: length(vulnerable(with_marker, labels)),
          without_marker: length(without_marker),
          vulnerable_without: length(vulnerable(without_marker, labels))
        }
      end)

    %{per_year: per_year, repo_files: repo_markers}
  end
end
