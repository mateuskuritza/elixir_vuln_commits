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

  defp print_summary(summary) do
    Mix.shell().info("""

    commits:               #{summary.commits}
    vulneraveis:           #{summary.vulnerable}
    arquivos:              #{summary.files}
    arquivos em vuln.:     #{summary.files_in_vulnerable}
    repos com vuln.:       #{summary.repos_with_vulnerable}
    """)
  end

  defp print_per_year(per_year) do
    Mix.shell().info("ano   commits  vuln.  proporcao")

    sorted = Enum.sort(per_year)

    Enum.each(sorted, fn {year, numbers} ->
      commits = pad(numbers.commits, 7)
      vulnerable = pad(numbers.vulnerable, 5)
      Mix.shell().info("#{year}  #{commits}  #{vulnerable}  #{numbers.proportion}%")
    end)
  end

  defp pad(number, width) do
    text = Integer.to_string(number)
    String.pad_leading(text, width)
  end
end
