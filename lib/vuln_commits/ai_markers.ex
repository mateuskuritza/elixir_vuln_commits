# marcadores de ferramentas de IA na mensagem e nos arquivos do repositório
defmodule VulnCommits.AiMarkers do
  alias VulnCommits.Text

  # lista fixa, em minúsculas. "co-authored-by" fica coberto pelos nomes.
  @markers ~w(copilot claude chatgpt gpt- cursor codex devin aider gemini ai-generated)

  # arquivos de instrução para agentes de IA
  @repo_files ~w(AGENTS.md CLAUDE.md .cursorrules .cursor/rules
                 .github/copilot-instructions.md GEMINI.md .windsurfrules)

  def markers, do: @markers

  def repo_files, do: @repo_files

  # marcadores que aparecem na mensagem, na ordem da lista e sem repetir.
  # "cursor" também casa o sentido de posição do editor (falso positivo conhecido).
  def in_message(message) do
    text = message |> Text.scrub() |> String.downcase()
    Enum.filter(@markers, fn marker -> String.contains?(text, marker) end)
  end
end
