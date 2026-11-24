defmodule VulnCommits.PopulationTest do
  use ExUnit.Case, async: true

  alias VulnCommits.{Commit, Population}

  test "fisher bate com o valor de referência" do
    # scipy.stats.fisher_exact([[3, 7], [1, 9]]) -> p = 0.5820...
    assert_in_delta Population.fisher(3, 10, 1, 10), 0.5820, 0.001
    assert_in_delta Population.fisher(5, 5, 0, 5), 0.0079, 0.001
  end

  test "padroniza pela distribuição de tamanho de mensagem da referência" do
    short = %Commit{hash: "a", message: "fix"}
    long = %Commit{hash: "b", message: Enum.map_join(1..60, " ", fn _ -> "w" end)}
    labels = %{"a" => %{final: :neutral}, "b" => %{final: :vulnerable}}

    # na referência só há mensagens curtas, então a taxa padronizada é a das curtas
    assert Population.standardized([short, long], [short], labels) == 0.0
    assert Population.standardized([short, long], [short, long], labels) == 50.0
  end
end
