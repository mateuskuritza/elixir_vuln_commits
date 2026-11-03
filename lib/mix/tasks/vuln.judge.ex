defmodule Mix.Tasks.Vuln.Judge do
  use Mix.Task

  alias VulnCommits.{Collect, Judge, Repos}
  alias VulnCommits.Judge.{OpenAI, Prompt, Store}

  @shortdoc "Julga os candidatos com o modelo (3 runs por commit)"

  @commits "data/commits.csv"
  @repos "data/repos.csv"
  @judgments "data/judgments.jsonl"
  @confirm_limit 200

  @impl Mix.Task
  def run(args) do
    Application.ensure_all_started(:req)
    opts = parse_args(args)

    commits = Collect.load(@commits)
    dirs = @repos |> Repos.load() |> Map.new(&{&1.name, &1.dir})
    candidates = Judge.candidates(commits, opts.period, years: opts.years)

    model = OpenAI.model()
    version = Prompt.version()
    done = @judgments |> Store.load() |> Store.done()
    pairs = Judge.pending(candidates, done, model, version)
    calls = length(pairs)

    Mix.shell().info("periodo: #{opts.period}  anos: #{years_text(opts.years)}")
    Mix.shell().info("candidatos: #{length(candidates)}")
    Mix.shell().info("chamadas pendentes: #{calls}")
    Mix.shell().info("modelo: #{model}  prompt: #{version}")
    Mix.shell().info("custo estimado: #{cost_text(calls)}")

    cond do
      opts.dry_run ->
        Mix.shell().info("dry-run: nenhuma chamada feita")

      should_run?(calls, opts) ->
        if api_key_ok?(System.get_env("OPENAI_API_KEY")) do
          Judge.run(pairs,
            dirs: dirs,
            path: @judgments,
            model: model,
            version: version
          )
        else
          Mix.raise(
            "OPENAI_API_KEY não definida ou vazia. defina a chave no ambiente (ou no .env) e rode de novo. nada foi julgado."
          )
        end

      true ->
        Mix.shell().info("mais de #{@confirm_limit} chamadas: rode de novo com --yes")
    end
  end

  # lê as opções da linha de comando; periodo é obrigatório
  def parse_args(args) do
    {parsed, _rest, _invalid} =
      OptionParser.parse(args,
        strict: [period: :string, years: :string, dry_run: :boolean, yes: :boolean]
      )

    %{
      period: parse_period(parsed[:period]),
      years: parse_years(parsed[:years]),
      dry_run: Keyword.get(parsed, :dry_run, false),
      yes: Keyword.get(parsed, :yes, false)
    }
  end

  defp parse_period("original"), do: :original
  defp parse_period("extended"), do: :extended

  defp parse_period(other) do
    raise ArgumentError, "use --period original|extended (recebido: #{inspect(other)})"
  end

  defp parse_years(nil), do: nil

  defp parse_years(text) do
    case String.split(text, "-") do
      [from, to] -> String.to_integer(from)..String.to_integer(to)
      _ -> raise ArgumentError, "use --years AAAA-AAAA (recebido: #{inspect(text)})"
    end
  end

  # dry-run nunca chama a api; acima de 200 chamadas só com --yes
  def should_run?(calls, opts) do
    cond do
      opts.dry_run -> false
      calls > @confirm_limit -> opts.yes
      true -> true
    end
  end

  # chave ausente ou vazia impede qualquer chamada; a tarefa para antes de gravar erros no jsonl
  def api_key_ok?(key), do: key not in [nil, ""]

  defp years_text(nil), do: "todos"
  defp years_text(first..last//_), do: "#{first}-#{last}"

  defp cost_text(calls) do
    case OpenAI.estimate_cost(calls) do
      nil -> "sem preço para o modelo"
      cost -> "US$ #{Float.round(cost, 2)}"
    end
  end
end
