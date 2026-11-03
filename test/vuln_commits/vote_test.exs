defmodule VulnCommits.VoteTest do
  use ExUnit.Case, async: true
  alias VulnCommits.Vote

  test "majority: 2 vulnerable de 3 vira vulnerable" do
    assert Vote.majority([:vulnerable, :vulnerable, :neutral]) == :vulnerable
  end

  test "majority: 2 neutral de 3 vira neutral" do
    assert Vote.majority([:neutral, :neutral, :vulnerable]) == :neutral
  end

  test "majority: 2 erros deixam indefinido" do
    assert Vote.majority([:vulnerable, :error, :error]) == :undecided
  end

  test "majority: um voto para cada lado deixa indefinido" do
    assert Vote.majority([:vulnerable, :neutral, :error]) == :undecided
  end

  test "majority com lista vazia é indefinido" do
    assert Vote.majority([]) == :undecided
  end

  test "unanimous? é verdadeiro so quando todos os rotulos são iguais" do
    assert Vote.unanimous?([:vulnerable, :vulnerable, :vulnerable])
    refute Vote.unanimous?([:vulnerable, :vulnerable, :neutral])
  end

  test "unanimous? com lista vazia é falso" do
    refute Vote.unanimous?([])
  end
end
