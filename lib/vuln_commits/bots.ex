# bots de dependência e ci: commits deles ficam fora da proporção de 2021 a 2025
defmodule VulnCommits.Bots do
  alias VulnCommits.Commit

  # nomes que aparecem no autor ou no e-mail de bots conhecidos
  @names ["dependabot", "renovate", "github-actions", "greenkeeper"]

  # e-mail noreply de conta bot do github, ex.: 49699333+dependabot[bot]@users.noreply.github.com
  @noreply ~r/^\d+\+.*\[bot\]@users\.noreply\.github\.com$/

  # nil vira "" para não quebrar em commits sem autor
  def bot?(%Commit{author_name: name, author_email: email}) do
    Enum.any?([name, email], &bot_text?(String.downcase(&1 || "")))
  end

  defp bot_text?(text) do
    Enum.any?(@names, &String.contains?(text, &1)) or
      String.ends_with?(text, "[bot]") or
      Regex.match?(@noreply, text)
  end
end
