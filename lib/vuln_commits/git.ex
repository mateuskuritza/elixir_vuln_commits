# acesso ao git por linha de comando
defmodule VulnCommits.Git do
  alias VulnCommits.Text

  # separadores do formato do log: 0x1f entre campos, 0x1e entre commits
  @format "%H%x1f%cI%x1f%an%x1f%ae%x1f%P%x1f%B%x1e"

  def clone_url(owner_repo), do: "https://github.com/#{owner_repo}.git"

  def clone(owner_repo, dir), do: clone_from(clone_url(owner_repo), dir)

  # clone sem checkout (só o histórico) e depois traz branches e tags
  defp clone_from(url, dir) do
    with {_, 0} <-
           System.cmd("git", ["clone", "--no-checkout", "-q", url, dir], stderr_to_stdout: true),
         {_, 0} <-
           System.cmd(
             "git",
             [
               "fetch",
               "-q",
               "origin",
               "+refs/heads/*:refs/remotes/origin/*",
               "+refs/tags/*:refs/tags/*"
             ],
             cd: dir,
             stderr_to_stdout: true
           ) do
      :ok
    else
      {out, _code} -> {:error, out}
    end
  end

  def default_branch(dir) do
    dir
    |> git!(["symbolic-ref", "refs/remotes/origin/HEAD"])
    |> String.trim()
    |> String.replace_prefix("refs/remotes/origin/", "")
  end

  def head(dir, ref), do: dir |> git!(["rev-parse", ref]) |> String.trim()

  # sai com código diferente de 0 quando o objeto não existe, então não usa git!
  def object_exists?(dir, hash) do
    {_, status} =
      System.cmd("git", ["cat-file", "-e", hash <> "^{commit}"], cd: dir, stderr_to_stdout: true)

    status == 0
  end

  # o git filtra com folga de um dia em cada ponta e a regra de verdade é aqui,
  # pela data do commit (a do próprio fuso dele)
  def log(dir, ref, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)

    args =
      [
        "log",
        "--format=" <> @format,
        "--since=#{Date.add(since, -1)}T00:00:00",
        "--until=#{Date.add(until, 1)}T23:59:59"
      ] ++
        if(Keyword.get(opts, :no_merges, false), do: ["--no-merges"], else: []) ++ [ref]

    dir
    |> git!(args)
    |> parse_log()
    |> Enum.filter(&in_range?(&1.date, since, until))
  end

  defp in_range?(date, since, until) do
    Date.compare(date, since) != :lt and Date.compare(date, until) != :gt
  end

  # função pura: texto do git log -> lista de mapas
  def parse_log(binary) do
    binary
    |> Text.scrub()
    |> String.split(<<0x1E>>)
    |> Enum.map(&String.trim_leading(&1, "\n"))
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&parse_record/1)
  end

  defp parse_record(record) do
    [hash, date, name, email, parents, message] = String.split(record, <<0x1F>>, parts: 6)

    %{
      hash: hash,
      date: date |> binary_part(0, 10) |> Date.from_iso8601!(),
      author_name: name,
      author_email: email,
      message: String.trim_trailing(message, "\n"),
      merge?: length(String.split(parents, " ", trim: true)) >= 2
    }
  end

  def files(dir, hash) do
    dir
    |> git!(["-c", "core.quotepath=off", "show", "--format=", "--name-only", hash])
    |> String.split("\n", trim: true)
    |> Enum.sort()
  end

  # paths vazio devolve o diff inteiro
  def diff(dir, hash, paths) do
    args =
      ["show", "--format=", "--no-color", hash] ++ if(paths == [], do: [], else: ["--" | paths])

    dir |> git!(args) |> Text.scrub()
  end

  # data do commit que criou o arquivo, a partir do HEAD (a branch padrão do clone)
  def first_added(dir, path) do
    case dir
         |> git!(["log", "--diff-filter=A", "--format=%cI", "-1", "HEAD", "--", path])
         |> String.trim() do
      "" -> nil
      iso -> iso |> binary_part(0, 10) |> Date.from_iso8601!()
    end
  end

  def show_message(dir, hash) do
    dir
    |> git!(["show", "-s", "--format=" <> @format, hash])
    |> parse_log()
    |> hd()
  end

  defp git!(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {out, 0} -> out
      {out, code} -> raise "git #{Enum.join(args, " ")} falhou (#{code}): #{out}"
    end
  end
end
