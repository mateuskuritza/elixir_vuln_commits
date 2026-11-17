defmodule VulnCommits.Git do
  alias VulnCommits.Text

  @format "%H%x1f%cI%x1f%an%x1f%ae%x1f%P%x1f%B%x1e"

  def clone_url(owner_repo), do: "https://github.com/#{owner_repo}.git"

  def clone(owner_repo, dir), do: clone_from(clone_url(owner_repo), dir)

  defp clone_from(url, dir) do
    clone_args = ["clone", "--no-checkout", "-q", url, dir]

    case System.cmd("git", clone_args, stderr_to_stdout: true) do
      {_, 0} -> fetch_all_refs(dir)
      {out, _code} -> {:error, out}
    end
  end

  defp fetch_all_refs(dir) do
    fetch_args = [
      "fetch",
      "-q",
      "origin",
      "+refs/heads/*:refs/remotes/origin/*",
      "+refs/tags/*:refs/tags/*"
    ]

    case System.cmd("git", fetch_args, cd: dir, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {out, _code} -> {:error, out}
    end
  end

  def update(dir) do
    case System.cmd("git", ["fetch", "-q", "--all", "--tags"], cd: dir, stderr_to_stdout: true) do
      {_, 0} ->
        git!(dir, ["update-ref", "HEAD", "refs/remotes/origin/HEAD"])
        :ok

      {out, _code} ->
        {:error, out}
    end
  end

  def default_branch(dir) do
    output = git!(dir, ["symbolic-ref", "refs/remotes/origin/HEAD"])
    ref = String.trim(output)
    String.replace_prefix(ref, "refs/remotes/origin/", "")
  end

  def head(dir, ref) do
    output = git!(dir, ["rev-parse", ref])
    String.trim(output)
  end

  def object_exists?(dir, hash) do
    {_, status} =
      System.cmd("git", ["cat-file", "-e", hash <> "^{commit}"], cd: dir, stderr_to_stdout: true)

    status == 0
  end

  def log(dir, ref, opts) do
    since = Keyword.fetch!(opts, :since)
    until = Keyword.fetch!(opts, :until)
    no_merges = Keyword.get(opts, :no_merges, false)

    base_args = [
      "log",
      "--format=" <> @format,
      "--until=#{Date.add(until, 1)}T23:59:59"
    ]

    args =
      if no_merges do
        base_args ++ ["--no-merges", ref]
      else
        base_args ++ [ref]
      end

    output = git!(dir, args)
    entries = parse_log(output)
    Enum.filter(entries, fn entry -> in_range?(entry.date, since, until) end)
  end

  defp in_range?(date, since, until) do
    Date.compare(date, since) != :lt and Date.compare(date, until) != :gt
  end

  def parse_log(binary) do
    text = Text.scrub(binary)
    records = String.split(text, <<0x1E>>)
    records = Enum.map(records, fn record -> String.trim_leading(record, "\n") end)
    records = Enum.reject(records, fn record -> record == "" end)
    Enum.map(records, fn record -> parse_record(record) end)
  end

  defp parse_record(record) do
    [hash, date, name, email, parents, message] = String.split(record, <<0x1F>>, parts: 6)
    parent_list = String.split(parents, " ", trim: true)

    %{
      hash: hash,
      date: to_date(date),
      author_name: name,
      author_email: email,
      message: String.trim_trailing(message, "\n"),
      merge?: length(parent_list) >= 2
    }
  end

  defp to_date(iso) do
    day = binary_part(iso, 0, 10)
    Date.from_iso8601!(day)
  end

  def files(dir, hash) do
    output = git!(dir, ["-c", "core.quotepath=off", "show", "--format=", "--name-only", hash])
    lines = String.split(output, "\n", trim: true)
    Enum.sort(lines)
  end

  def diff(dir, hash, paths) do
    base_args = ["show", "--format=", "--no-color", hash]

    args =
      if paths == [] do
        base_args
      else
        base_args ++ ["--"] ++ paths
      end

    output = git!(dir, args)
    Text.scrub(output)
  end

  def first_added(dir, path) do
    output = git!(dir, ["log", "--diff-filter=A", "--format=%cI", "-1", "HEAD", "--", path])

    case String.trim(output) do
      "" -> nil
      iso -> to_date(iso)
    end
  end

  def show_message(dir, hash) do
    output = git!(dir, ["show", "-s", "--format=" <> @format, hash])
    entries = parse_log(output)
    hd(entries)
  end

  defp git!(dir, args) do
    case System.cmd("git", args, cd: dir, stderr_to_stdout: true) do
      {out, 0} -> out
      {out, code} -> raise "git #{Enum.join(args, " ")} falhou (#{code}): #{out}"
    end
  end
end
