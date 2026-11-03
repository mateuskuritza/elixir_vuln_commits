defmodule VulnCommits.BotsTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Bots
  alias VulnCommits.Commit

  test "reconhece bots pelo nome do autor" do
    assert Bots.bot?(%Commit{author_name: "dependabot[bot]"})
    assert Bots.bot?(%Commit{author_name: "renovate-bot"})
    assert Bots.bot?(%Commit{author_name: "github-actions"})
    assert Bots.bot?(%Commit{author_name: "greenkeeper"})
  end

  test "reconhece bots pelo e-mail noreply do github" do
    assert Bots.bot?(%Commit{
             author_name: "dependabot",
             author_email: "49699333+dependabot[bot]@users.noreply.github.com"
           })
  end

  test "autor humano nao e bot" do
    refute Bots.bot?(%Commit{author_name: "José Valim", author_email: "jose@dashbit.co"})
  end

  test "campos nil nao quebram e nao viram bot" do
    refute Bots.bot?(%Commit{author_name: nil, author_email: nil})
  end
end
