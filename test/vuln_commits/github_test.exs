defmodule VulnCommits.GitHubTest do
  use ExUnit.Case, async: true

  alias VulnCommits.GitHub

  test "repo_info devolve estrelas, arquivado e branch padrão" do
    Req.Test.stub(VulnCommits.GitHub, fn conn ->
      Req.Test.json(conn, %{
        "stargazers_count" => 5,
        "archived" => false,
        "default_branch" => "main"
      })
    end)

    assert GitHub.repo_info("a/b") == {:ok, %{stars: 5, archived: false, default_branch: "main"}}
  end

  test "repo_info devolve erro quando o repositório não existe" do
    Req.Test.stub(VulnCommits.GitHub, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "Not Found"})
    end)

    assert {:error, _} = GitHub.repo_info("a/b")
  end
end
