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
    repo_rows = Repos.load(@repos)
    dirs = Map.new(repo_rows, fn repo -> {repo.name, repo.dir} end)
    version = Prompt.version()
    model = Batch.model()
    records = Store.load(@judgments)
    done = Store.done(records)

    candidates = Judge.candidates(commits, opts.period, years: opts.years)

    pending =
      Enum.reject(candidates, fn commit ->
        MapSet.member?(done, {commit.hash, opts.run, model, version})
      end)

    diff_fun = fn commit ->
      dir = Map.fetch!(dirs, commit.repo)
      Prompt.diff_for(commit, dir)
    end

    batches =
      Batch.export(pending, opts.out,
        batch_size: opts.batch_size,
        version: version,
        diff_fun: diff_fun
      )

    index =
      Enum.map(batches, fn batch ->
        %{path: batch.path, hashes: batch.hashes}
      end)

    index_path = Path.join(opts.out, "index.json")
    File.write!(index_path, Jason.encode!(index, pretty: true))

    Mix.shell().info(
      "#{length(pending)} commits pendentes em #{length(batches)} lotes em #{opts.out}"
    )
  end

  def run(["import" | args]) do
    opts = parse(args)
    all_commits = Collect.load(@commits)
    commits = Map.new(all_commits, fn commit -> {commit.hash, commit} end)
    index_path = Path.join(opts.out, "index.json")
    index = Jason.decode!(File.read!(index_path))

    Enum.each(index, fn %{"path" => path, "hashes" => hashes} ->
      import_batch(path, hashes, commits, opts)
    end)
  end

  defp import_batch(path, hashes, commits, opts) do
    answer = String.replace_suffix(path, ".md", ".out.jsonl")
    imported = answer <> ".imported"

    if File.exists?(imported) do
      :ok
    else
      if File.exists?(answer) do
        case Batch.parse(File.read!(answer), hashes) do
          {:ok, judgments} ->
            Batch.store(judgments, commits, @judgments,
              run: opts.run,
              model: Batch.model(),
              version: Prompt.version()
            )

            File.rename!(answer, imported)
            Mix.shell().info("importado #{answer} (#{length(judgments)})")

          {:error, why} ->
            Mix.shell().error("resposta inválida em #{answer}: #{inspect(why)}")
        end
      else
        Mix.shell().info("sem resposta ainda: #{answer}")
      end
    end
  end

  defp parse(args) do
    {parsed, _rest, _invalid} =
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
      period: period(parsed[:period]),
      years: years(parsed[:years]),
      run: Keyword.fetch!(parsed, :run),
      out: Keyword.fetch!(parsed, :out),
      batch_size: Keyword.get(parsed, :batch_size, 20)
    }
  end

  defp period(nil), do: nil
  defp period(text), do: String.to_existing_atom(text)

  defp years(nil), do: nil

  defp years(text) do
    [first, last] = String.split(text, "-")
    String.to_integer(first)..String.to_integer(last)
  end
end
