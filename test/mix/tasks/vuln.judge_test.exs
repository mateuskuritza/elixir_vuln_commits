defmodule Mix.Tasks.Vuln.JudgeTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Vuln.Judge, as: JudgeTask

  test "parse_args le periodo e anos" do
    assert %{period: :original, years: 2012..2016, dry_run: false, yes: false} =
             JudgeTask.parse_args(["--period", "original", "--years", "2012-2016"])
  end

  test "parse_args sem anos deixa nil e le as flags" do
    assert %{period: :extended, years: nil, dry_run: true, yes: true} =
             JudgeTask.parse_args(["--period", "extended", "--dry-run", "--yes"])
  end

  test "parse_args recusa periodo ausente ou invalido" do
    assert_raise ArgumentError, fn -> JudgeTask.parse_args([]) end
    assert_raise ArgumentError, fn -> JudgeTask.parse_args(["--period", "outro"]) end
  end

  test "should_run? nunca roda com dry-run" do
    refute JudgeTask.should_run?(10, %{dry_run: true, yes: true})
  end

  test "should_run? roda ate 200 chamadas sem --yes" do
    assert JudgeTask.should_run?(200, %{dry_run: false, yes: false})
  end

  test "should_run? para acima de 200 chamadas sem --yes" do
    refute JudgeTask.should_run?(201, %{dry_run: false, yes: false})
  end

  test "should_run? roda acima de 200 com --yes" do
    assert JudgeTask.should_run?(201, %{dry_run: false, yes: true})
  end

  test "api_key_ok? recusa chave ausente ou vazia" do
    assert JudgeTask.api_key_ok?("sk-teste")
    refute JudgeTask.api_key_ok?(nil)
    refute JudgeTask.api_key_ok?("")
  end
end
