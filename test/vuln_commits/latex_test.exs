defmodule VulnCommits.LatexTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Latex

  test "tabela tem booktabs e escapa o underscore" do
    tex = Latex.table(["a", "b"], [[1, "x_y"]], "c", "l")

    assert tex =~ "\\toprule"
    assert tex =~ "\\midrule"
    assert tex =~ "\\bottomrule"
    assert tex =~ "x\\_y"
    assert tex =~ "\\begin{table}"
    assert tex =~ "\\end{table}"
    assert tex =~ "\\caption{c}"
    assert tex =~ "\\label{l}"
  end

  test "escapa porcentagem, e comercial e cerquilha" do
    tex = Latex.table(["p (%)"], [["a & b # c"]], "x", "y")
    assert tex =~ "p (\\%)"
    assert tex =~ "a \\& b \\# c"
  end

  test "inteiro fica inteiro, float tem duas casas e nil vira traço duplo" do
    tex = Latex.table(["n", "p", "q"], [[4446, 2.0, nil], [3, 18.0312, 1.5]], "c", "l")
    assert tex =~ "4446 & 2.00 & -- \\\\"
    assert tex =~ "3 & 18.03 & 1.50 \\\\"
  end

  test "maior ou igual vira símbolo matemático" do
    tex = Latex.table(["m"], [["com ≥1"]], "c", "l")
    assert tex =~ "com $\\geq$1"
  end
end
