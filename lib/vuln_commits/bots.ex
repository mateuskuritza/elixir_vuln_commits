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
    has_bot_name = Enum.any?(@names, fn name -> String.contains?(text, name) end)
    ends_with_bot = String.ends_with?(text, "[bot]")
    is_noreply_bot = Regex.match?(@noreply, text)

    has_bot_name or ends_with_bot or is_noreply_bot
  end
end
