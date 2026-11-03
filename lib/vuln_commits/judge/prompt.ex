# prompt do estágio 2: o que vai para o modelo e como o diff é cortado
defmodule VulnCommits.Judge.Prompt do
  alias VulnCommits.Commit
  alias VulnCommits.Git

  @max_bytes 12_000

  # versão do prompt vem do ambiente; padrão v1
  def version, do: System.get_env("OPENAI_PROMPT_VERSION", "v1")

  # conteúdo de priv/prompts/<version>.md
  def system(version) do
    :vuln_commits
    |> Application.app_dir("priv/prompts/#{version}.md")
    |> File.read!()
  end

  # diff só dos arquivos elixir; se o commit não tem nenhum, o diff inteiro
  def diff_for(%Commit{hash: hash, elixir_files: elixir_files}, dir) do
    diff =
      case Git.diff(dir, hash, elixir_files) do
        "" -> Git.diff(dir, hash, [])
        diff -> diff
      end

    truncate(diff, @max_bytes)
  end

  # corta em no máximo max_bytes bytes sem quebrar caractere utf-8
  def truncate(diff, max_bytes \\ @max_bytes) do
    if byte_size(diff) <= max_bytes do
      diff
    else
      cut = diff |> binary_part(0, max_bytes) |> valid_prefix()
      cut <> "\n[... diff truncated at #{max_bytes} bytes ...]"
    end
  end

  # um corte no meio de um caractere deixa bytes inválidos no fim.
  # tira um byte por vez até sobrar um prefixo utf-8 válido (no máximo 3 voltas)
  defp valid_prefix(bin) do
    if String.valid?(bin) do
      bin
    else
      valid_prefix(binary_part(bin, 0, byte_size(bin) - 1))
    end
  end

  # mensagem do usuário: repositório, data, mensagem, arquivos e o diff em bloco
  def user(commit, diff) do
    files = Enum.map_join(commit.files, "\n", &"- #{&1}")

    """
    Repository: #{commit.repo}
    Date: #{commit.date}
    Commit message:
    #{commit.message}

    Changed files:
    #{files}

    Diff:
    ```diff
    #{String.trim_trailing(diff)}
    ```
    """
  end

  # JSON Schema do structured output (strict): só os três campos, sem extras
  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "label" => %{"type" => "string", "enum" => ["VULNERABLE", "NEUTRAL"]},
        "cia" => %{
          "type" => "string",
          "enum" => ["confidentiality", "integrity", "availability", "none"]
        },
        "reason" => %{"type" => "string"}
      },
      "required" => ["label", "cia", "reason"],
      "additionalProperties" => false
    }
  end
end
