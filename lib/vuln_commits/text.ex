defmodule VulnCommits.Text do
  def scrub(binary) do
    binary
    |> String.chunk(:valid)
    |> Enum.filter(&String.valid?/1)
    |> Enum.join()
  end
end
