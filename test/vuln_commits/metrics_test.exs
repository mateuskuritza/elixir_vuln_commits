defmodule VulnCommits.MetricsTest do
  use ExUnit.Case, async: true
  alias VulnCommits.Metrics

  test "proportion devolve porcentagem com 2 casas" do
    assert Metrics.proportion(1, 3) == 33.33
    assert Metrics.proportion(2, 4) == 50.0
  end

  test "proportion com total zero devolve 0.0" do
    assert Metrics.proportion(0, 0) == 0.0
  end
end
