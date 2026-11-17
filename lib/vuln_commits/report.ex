defmodule VulnCommits.Report do
  alias VulnCommits.{Metrics, Vote}

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

  defp ours(labels, commit), do: final(Map.fetch!(labels, commit.hash).final)
  defp final(:undecided), do: :neutral
  defp final(label), do: label

  defp human_labels(commits) do
    Map.new(commits, &{&1.hash, %{votes: [], final: &1.human_label}})
  end

  defp vulnerable(commits, label_fun), do: Enum.filter(commits, &(label_fun.(&1) == :vulnerable))

  def match(original, labels) do
    human = human_labels(original)
    columns = [{:human_active, human}, {:ours, labels}]
    stats = Map.new(columns, fn {key, map} -> {key, stats(original, map)} end)

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

    for {name, key} <- metrics do
      %{
        metric: name,
        paper: paper_value(key),
        human_active: stats.human_active[key],
        ours: stats.ours[key]
      }
    end
  end

  defp paper_value(:files_pct),
    do: Metrics.proportion(@paper_totals.files_in_vulnerable, @paper_totals.files)

  defp paper_value(key), do: Map.fetch!(@paper_totals, key)

  defp stats(commits, labels) do
    vuln = vulnerable(commits, &ours(labels, &1))

    %{
      commits: length(commits),
      vulnerable: length(vuln),
      proportion: Metrics.proportion(length(vuln), length(commits)),
      repos: commits |> Enum.map(& &1.repo) |> Enum.uniq() |> length(),
      repos_with_vulnerable: vuln |> Enum.map(& &1.repo) |> Enum.uniq() |> length(),
      files: count_files(commits),
      files_in_vulnerable: count_files(vuln),
      files_pct: files_pct(commits, labels)
    }
  end

  defp count_files(commits) do
    commits
    |> Enum.flat_map(fn c -> Enum.map(c.elixir_files, &{c.repo, &1}) end)
    |> Enum.uniq()
    |> length()
  end

  def files_pct(commits, labels) do
    vuln = vulnerable(commits, &ours(labels, &1))
    Metrics.proportion(count_files(vuln), count_files(commits))
  end

  def per_year(original, extended, labels) do
    human = human_labels(original)
    by_year = Enum.group_by(original, & &1.year)
    ext_by_year = extended |> Enum.reject(& &1.bot) |> Enum.group_by(& &1.year)

    for year <- 2012..2025 do
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
        group = Map.get(ext_by_year, year, [])

        %{
          year: year,
          commits: length(group),
          paper: nil,
          human_active: nil,
          ours: share(group, labels)
        }
      end
    end
  end

  defp share(commits, labels) do
    Metrics.proportion(length(vulnerable(commits, &ours(labels, &1))), length(commits))
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
    pairs = for c <- original, c.year in years, do: {c.human_label, ours(labels, c)}
    confusion = Metrics.confusion(pairs)

    %{n: length(pairs), confusion: confusion, kappa: Metrics.cohen_kappa(pairs)}
    |> Map.merge(Metrics.precision_recall_f1(confusion))
  end

  defp runs(commits, labels) do
    finals = for c <- commits, do: Map.fetch!(labels, c.hash)
    triples = for %{votes: [_, _, _] = votes} <- finals, do: votes
    undecided = Enum.count(finals, &(&1.final == :undecided))

    if triples == [] do
      %{n: 0, mean_kappa: nil, min_kappa: nil, unanimous_pct: nil, undecided: undecided}
    else
      per_run = Enum.zip_with(triples, & &1)
      kappa = Metrics.pairwise_kappa(per_run)

      %{
        n: length(triples),
        mean_kappa: kappa.mean,
        min_kappa: kappa.min,
        unanimous_pct:
          Metrics.proportion(Enum.count(triples, &Vote.unanimous?/1), length(triples)),
        undecided: undecided
      }
    end
  end

  def bots(extended) do
    by_year = Enum.group_by(extended, & &1.year)

    for year <- 2021..2025 do
      group = Map.get(by_year, year, [])
      %{year: year, bots: Enum.count(group, & &1.bot), total: length(group)}
    end
  end

  def ai(extended, labels, repo_markers) do
    by_year = extended |> Enum.reject(& &1.bot) |> Enum.group_by(& &1.year)

    per_year =
      for year <- 2021..2025 do
        {with, without} = by_year |> Map.get(year, []) |> Enum.split_with(&(&1.ai_markers != []))

        %{
          year: year,
          with_marker: length(with),
          vulnerable_with: length(vulnerable(with, &ours(labels, &1))),
          without_marker: length(without),
          vulnerable_without: length(vulnerable(without, &ours(labels, &1)))
        }
      end

    %{per_year: per_year, repo_files: repo_markers}
  end
end
