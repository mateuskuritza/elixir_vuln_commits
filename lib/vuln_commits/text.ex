# limpeza de texto que vem de fora (csv, git log)
defmodule VulnCommits.Text do
  # tira os bytes que não são utf-8 válido (descarta, não troca por U+FFFD)
  def scrub(binary) do
    binary
    |> String.chunk(:valid)
    |> Enum.filter(&String.valid?/1)
    |> Enum.join()
  end
end
