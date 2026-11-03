defmodule VulnCommits.AiMarkersTest do
  use ExUnit.Case, async: true

  alias VulnCommits.AiMarkers

  test "marcadores da mensagem na ordem da lista" do
    assert AiMarkers.in_message("Co-authored-by: Copilot <copilot@github.com>") == ["copilot"]
    assert AiMarkers.in_message("Generated with Claude Code") == ["claude"]
    assert AiMarkers.in_message("ask chatgpt and gpt-4 about it") == ["chatgpt", "gpt-"]
  end

  test "palavra comum com marcador dentro (falso positivo conhecido)" do
    # cursor aparece no sentido de posicao do editor; fica documentado no artigo
    assert AiMarkers.in_message("move cursor to end") == ["cursor"]
  end

  test "mensagem nil nao quebra" do
    assert AiMarkers.in_message(nil) == []
  end

  test "mensagem sem marcador" do
    assert AiMarkers.in_message("fix typo") == []
  end

  test "nao repete marcador" do
    assert AiMarkers.in_message("claude claude CLAUDE") == ["claude"]
  end

  test "lista de marcadores de IA" do
    assert AiMarkers.markers() == [
             "copilot",
             "claude",
             "chatgpt",
             "gpt-",
             "cursor",
             "codex",
             "devin",
             "aider",
             "gemini",
             "ai-generated"
           ]
  end

  test "arquivos de instrução de agentes" do
    assert "CLAUDE.md" in AiMarkers.repo_files()
    assert ".github/copilot-instructions.md" in AiMarkers.repo_files()
  end
end
