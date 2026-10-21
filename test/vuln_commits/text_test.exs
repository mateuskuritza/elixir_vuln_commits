defmodule VulnCommits.TextTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Text

  test "descarta bytes invalidos sem trocar por substituto" do
    assert Text.scrub(<<"ab", 0xFF, "c">>) == "abc"
  end

  test "texto valido passa igual, com acento" do
    assert Text.scrub("correção rápida") == "correção rápida"
  end
end
