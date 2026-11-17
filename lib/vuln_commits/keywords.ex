defmodule VulnCommits.Keywords do
  alias VulnCommits.Text

  @suffixes ["s", "es", "ed", "d", "ing", "er", "ers"]

  def terms do
    ~w(race racy buffer overflow stack integer signedness widthness underflow
       improper unauthenticated) ++
      ["gain access"] ++
      ~w(permission) ++
      ["cross site"] ++
      ~w(css xss htmlspecialchar) ++
      ["denial service"] ++
      ~w(dos crash deadlock sql sqli injection format string printf scanf) ++
      ["request forgery"] ++
      ~w(csrf xsrf forged security vulnerability vulnerable hole exploit attack
         bypass backdoor threat expose breach violate fatal blacklist overrun insecure)
  end

  def normalize(text) do
    clean_text = Text.scrub(text)
    lower_text = String.downcase(clean_text)
    only_words = Regex.replace(~r/[^a-z0-9_]+/, lower_text, " ")
    String.trim(only_words)
  end

  def match(text) do
    normalized = normalize(text)
    tokens = String.split(normalized, " ", trim: true)

    Enum.filter(terms(), fn term -> term_found?(tokens, term) end)
  end

  def hit?(text), do: match(text) != []

  defp term_found?(tokens, term) do
    words = String.split(term, " ")
    forms = Enum.map(words, fn word -> token_forms(word) end)
    match_at?(tokens, forms)
  end

  defp token_forms(token) do
    with_suffixes = Enum.map(@suffixes, fn suffix -> token <> suffix end)
    [token] ++ with_suffixes ++ stem_forms(token)
  end

  defp stem_forms(token) do
    stem = String.slice(token, 0..-2//1)

    if String.ends_with?(token, "e") do
      [stem <> "ing", stem <> "ion", stem <> "ions"]
    else
      if String.ends_with?(token, "y") do
        [stem <> "ies"]
      else
        []
      end
    end
  end

  defp match_at?([], _forms), do: false

  defp match_at?([_ | rest] = tokens, forms) do
    run?(tokens, forms) or match_at?(rest, forms)
  end

  defp run?(_tokens, []), do: true
  defp run?([], _forms), do: false

  defp run?([token | rest], [token_forms | forms_rest]) do
    token in token_forms and run?(rest, forms_rest)
  end
end
