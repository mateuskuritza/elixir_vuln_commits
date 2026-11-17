defmodule Mix.Tasks.Vuln.Dataset do
  use Mix.Task

  alias VulnCommits.Dataset

  @shortdoc "Baixa o dataset do figshare e imprime o resumo"

  @url "https://ndownloader.figshare.com/files/28993641"
  @path "data/figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv"

  @impl Mix.Task
  def run(_args) do
    Application.ensure_all_started(:req)
    download_if_missing()

    commits = Dataset.load(@path)
    print_summary(Dataset.summary(commits))
    print_per_year(Dataset.per_year(commits))
  end

  defp download_if_missing do
    if File.exists?(@path) do
      Mix.shell().info("usando #{@path}")
    else
      Mix.shell().info("baixando #{@url}")
      File.mkdir_p!(Path.dirname(@path))
      response = Req.get!(@url, decode_body: false, redirect_log_level: false)
      File.write!(@path, response.body)
    end
  end

  defp print_summary(s) do
    Mix.shell().info("""

    commits:               #{s.commits}
    vulneraveis:           #{s.vulnerable}
    arquivos:              #{s.files}
    arquivos em vuln.:     #{s.files_in_vulnerable}
    repos com vuln.:       #{s.repos_with_vulnerable}
    """)
  end

  defp print_per_year(per_year) do
    Mix.shell().info("ano   commits  vuln.  proporcao")

    per_year
    |> Enum.sort()
    |> Enum.each(fn {year, m} ->
      Mix.shell().info("#{year}  #{pad(m.commits, 7)}  #{pad(m.vulnerable, 5)}  #{m.proportion}%")
    end)
  end

  defp pad(n, width), do: n |> Integer.to_string() |> String.pad_leading(width)
end
