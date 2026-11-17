defmodule VulnCommits.Text do
  def scrub(binary) do
    chunks = String.chunk(binary, :valid)
    valid_chunks = Enum.filter(chunks, fn chunk -> String.valid?(chunk) end)
    Enum.join(valid_chunks)
  end
end
