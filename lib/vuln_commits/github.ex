defmodule VulnCommits.GitHub do
  @api "https://api.github.com/repos/"

  def repo_info(owner_repo) do
    options = Application.get_env(:vuln_commits, :github_req_options, [])

    case Req.get(@api <> owner_repo, [headers: headers()] ++ options) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok,
         %{
           stars: body["stargazers_count"],
           archived: body["archived"],
           default_branch: body["default_branch"]
         }}

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp headers do
    [{"accept", "application/vnd.github+json"}] ++
      case token() do
        nil -> []
        token -> [{"authorization", "Bearer " <> token}]
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
    with gh when is_binary(gh) <- System.find_executable("gh"),
         {out, 0} <- System.cmd(gh, ["auth", "token"], stderr_to_stdout: true),
         token when token != "" <- String.trim(out) do
      token
    else
      _ -> nil
    end
  end
end
