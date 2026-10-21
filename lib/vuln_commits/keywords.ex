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

  # o que pode vir colado no fim de um token do termo
  @suffixes ["s", "es", "ed", "d", "ing", "ion", "ions", "er", "ers", "y", "ies"]

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

    Enum.filter(@terms, fn term ->
      match_at?(tokens, String.split(term, " "))
    end)
  end

  def hit?(text), do: match(text) != []

  # o termo aparece em algum ponto da lista de tokens? (recursão na cabeça da lista)
  defp match_at?([], _term_tokens), do: false

  defp match_at?([_ | rest] = tokens, term_tokens) do
    run?(tokens, term_tokens) or match_at?(rest, term_tokens)
  end

  # tokens consecutivos a partir daqui casam com todos os tokens do termo
  defp run?(_tokens, []), do: true
  defp run?([], _term_tokens), do: false

  defp run?([token | rest], [term_token | term_rest]) do
    token in forms(term_token) and run?(rest, term_rest)
  end

  # formas aceitas de um token do termo: ele mesmo, mais sufixo, e as variações de e/y final
  defp forms(term_token) do
    stems =
      cond do
        String.ends_with?(term_token, "e") -> [term_token, String.slice(term_token, 0..-2//1)]
        String.ends_with?(term_token, "y") -> [term_token, String.slice(term_token, 0..-2//1)]
        true -> [term_token]
      end

    [term_token | for(stem <- stems, suffix <- @suffixes, do: stem <> suffix)]
  end
end
