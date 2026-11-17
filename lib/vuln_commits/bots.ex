defmodule VulnCommits.Bots do
  alias VulnCommits.Commit

  @names ["dependabot", "renovate", "github-actions", "greenkeeper"]

  @noreply ~r/^\d+\+.*\[bot\]@users\.noreply\.github\.com$/

  def bot?(%Commit{author_name: name, author_email: email}) do
    name = normalize(name)
    email = normalize(email)
    bot_text?(name) or bot_text?(email)
  end

  defp normalize(nil), do: ""
  defp normalize(text), do: String.downcase(text)

  defp bot_text?(text) do
    Enum.any?(@names, &String.contains?(text, &1)) or
      String.ends_with?(text, "[bot]") or
      Regex.match?(@noreply, text)
  end
end
