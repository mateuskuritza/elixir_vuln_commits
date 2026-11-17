defmodule VulnCommits.Keywords do
  alias VulnCommits.Text

  @terms ~w(race racy buffer overflow stack integer signedness widthness underflow
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

  @suffixes ["s", "es", "ed", "d", "ing", "er", "ers"]

  token_forms = fn token ->
    stem_forms =
      cond do
        String.ends_with?(token, "e") ->
          stem = String.slice(token, 0..-2//1)
          Enum.map(["ing", "ion", "ions"], &(stem <> &1))

        String.ends_with?(token, "y") ->
          [String.slice(token, 0..-2//1) <> "ies"]

        true ->
          []
      end

    [token | Enum.map(@suffixes, &(token <> &1))] ++ stem_forms
  end

  @term_forms Enum.map(@terms, fn term ->
                {term, Enum.map(String.split(term, " "), token_forms)}
              end)

  def terms, do: @terms

  def normalize(text) do
    text
    |> Text.scrub()
    |> String.downcase()
    |> then(&Regex.replace(~r/[^a-z0-9_]+/, &1, " "))
    |> String.trim()
  end

  def match(text) do
    tokens = text |> normalize() |> String.split(" ", trim: true)

    for {term, forms} <- @term_forms, match_at?(tokens, forms), do: term
  end

  def hit?(text), do: match(text) != []

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
