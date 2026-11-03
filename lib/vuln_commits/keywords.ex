# estágio 1: palavras-chave do artigo aplicadas na mensagem do commit
defmodule VulnCommits.Keywords do
  alias VulnCommits.Text

  # lista do artigo, termo composto escrito com espaço
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

  # sufixos que podem vir colados direto no token do termo
  @suffixes ["s", "es", "ed", "d", "ing", "er", "ers"]

  # formas aceitas de um token: ele mesmo, com sufixo, e o radical de termo em e ou y.
  # ex.: race -> racing, violate -> violations, vulnerability -> vulnerabilities
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

  # formas de cada termo, calculadas uma vez na compilação.
  # lista de {termo, [formas do 1o token, formas do 2o token, ...]}, na ordem de @terms
  @term_forms Enum.map(@terms, fn term ->
                {term, Enum.map(String.split(term, " "), token_forms)}
              end)

  def terms, do: @terms

  # minúsculas, tudo que não é [a-z0-9_] vira espaço, espaços colapsados
  def normalize(text) do
    text
    |> Text.scrub()
    |> String.downcase()
    |> then(&Regex.replace(~r/[^a-z0-9_]+/, &1, " "))
    |> String.trim()
  end

  # termos encontrados, sem repetir, na ordem de terms/0
  def match(text) do
    tokens = text |> normalize() |> String.split(" ", trim: true)

    for {term, forms} <- @term_forms, match_at?(tokens, forms), do: term
  end

  def hit?(text), do: match(text) != []

  # o termo aparece em algum ponto da lista de tokens? (recursão na cabeça da lista)
  defp match_at?([], _forms), do: false

  defp match_at?([_ | rest] = tokens, forms) do
    run?(tokens, forms) or match_at?(rest, forms)
  end

  # tokens consecutivos a partir daqui casam com as formas de cada token do termo
  defp run?(_tokens, []), do: true
  defp run?([], _forms), do: false

  defp run?([token | rest], [token_forms | forms_rest]) do
    token in token_forms and run?(rest, forms_rest)
  end
end
