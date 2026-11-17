defmodule VulnCommits.GitHub do
  @api "https://api.github.com/repos/"

  def repo_info(owner_repo) do
    options = Application.get_env(:vuln_commits, :github_req_options, [])
    request_options = [headers: headers()] ++ options

    case Req.get(@api <> owner_repo, request_options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        info = %{
          stars: body["stargazers_count"],
          archived: body["archived"],
          default_branch: body["default_branch"]
        }

        {:ok, info}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers do
    accept = {"accept", "application/vnd.github+json"}

    case token() do
      nil -> [accept]
      token -> [accept, {"authorization", "Bearer " <> token}]
    end
  end

  defp token do
    case System.get_env("GITHUB_TOKEN") do
      nil -> gh_token()
      "" -> gh_token()
      token -> token
    end
  end

  defp gh_token do
    case System.find_executable("gh") do
      nil -> nil
      gh -> token_from_gh(gh)
    end
  end

  defp token_from_gh(gh) do
    case System.cmd(gh, ["auth", "token"], stderr_to_stdout: true) do
      {out, 0} ->
        token = String.trim(out)

        if token == "" do
          nil
        else
          token
        end

      _ ->
        nil
    end
  end
end
