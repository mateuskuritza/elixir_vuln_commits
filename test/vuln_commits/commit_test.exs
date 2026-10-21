defmodule VulnCommits.CommitTest do
  use ExUnit.Case, async: true
  alias VulnCommits.Commit

  test "elixir_file? aceita .ex .exs .eex .heex .leex e rejeita o resto" do
    assert Commit.elixir_file?("lib/a.ex")
    assert Commit.elixir_file?("test/a_test.exs")
    assert Commit.elixir_file?("lib/t.html.heex")
    refute Commit.elixir_file?("README.md")
    refute Commit.elixir_file?("bin/iex")
  end

  test "year_of usa a data do commit" do
    assert Commit.year_of(%Commit{date: ~D[2019-11-27]}) == 2019
  end
end
