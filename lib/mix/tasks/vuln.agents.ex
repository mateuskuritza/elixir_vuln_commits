defmodule Mix.Tasks.Vuln.Agents do
  use Mix.Task

  alias VulnCommits.{Collect, Judge, Repos}
  alias VulnCommits.Judge.{Batch, Prompt, Store}

  @shortdoc "Exporta lotes para julgamento por agentes e importa as respostas"

  @commits "data/commits.csv"
  @repos "data/repos.csv"
  @judgments "data/judgments.jsonl"

  @impl Mix.Task
  def run(["export" | args]) do
    opts = parse(args)
    commits = Collect.load(@commits)
    dirs = @repos |> Repos.load() |> Map.new(&{&1.name, &1.dir})
    version = Prompt.version()
    done = @judgments |> Store.load() |> Store.done()

    pending =
      commits
      |> Judge.candidates(opts.period, years: opts.years)
      |> Enum.reject(&MapSet.member?(done, {&1.hash, opts.run, Batch.model(), version}))

    batches =
      Batch.export(pending, opts.out,
        batch_size: opts.batch_size,
        version: version,
        diff_fun: &Prompt.diff_for(&1, Map.fetch!(dirs, &1.repo))
      )

    index = Enum.map(batches, &%{path: &1.path, hashes: &1.hashes})
    File.write!(Path.join(opts.out, "index.json"), Jason.encode!(index, pretty: true))

    Mix.shell().info(
      "#{length(pending)} commits pendentes em #{length(batches)} lotes em #{opts.out}"
    )
  end

  def run(["import" | args]) do
    opts = parse(args)
    commits = @commits |> Collect.load() |> Map.new(&{&1.hash, &1})
    index = opts.out |> Path.join("index.json") |> File.read!() |> Jason.decode!()

    Enum.each(index, fn %{"path" => path, "hashes" => hashes} ->
      answer = String.replace_suffix(path, ".md", ".out.jsonl")

      with false <- File.exists?(answer <> ".imported"),
           true <- File.exists?(answer),
           {:ok, judgments} <- Batch.parse(File.read!(answer), hashes) do
        Batch.store(judgments, commits, @judgments,
          run: opts.run,
          model: Batch.model(),
          version: Prompt.version()
        )

        File.rename!(answer, answer <> ".imported")
        Mix.shell().info("importado #{answer} (#{length(judgments)})")
      else
        true -> :ok
        false -> Mix.shell().info("sem resposta ainda: #{answer}")
        {:error, why} -> Mix.shell().error("resposta inválida em #{answer}: #{inspect(why)}")
      end
    end)
  end

  defp parse(args) do
    {p, _, _} =
      OptionParser.parse(args,
        strict: [
          period: :string,
          years: :string,
          run: :integer,
          out: :string,
          batch_size: :integer
        ]
      )

    %{
      period: if(p[:period], do: String.to_existing_atom(p[:period])),
      years: years(p[:years]),
      run: Keyword.fetch!(p, :run),
      out: Keyword.fetch!(p, :out),
      batch_size: Keyword.get(p, :batch_size, 20)
    }
  end

  defp years(nil), do: nil

  defp years(text) do
    [a, b] = text |> String.split("-") |> Enum.map(&String.to_integer/1)
    a..b
  end
end
