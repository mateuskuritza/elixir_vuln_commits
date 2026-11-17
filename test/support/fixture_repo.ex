defmodule FixtureRepo do
  def create!() do
    dir = Path.join(System.tmp_dir!(), "vuln_fixture_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)

    git!(dir, ["init", "-q", "-b", "main"])
    git!(dir, ["config", "user.name", "Fulano"])
    git!(dir, ["config", "user.email", "fulano@example.com"])
    git!(dir, ["config", "commit.gpgsign", "false"])

    a = commit!(dir, "2020-05-01", "add lib", ["lib/a.ex"])
    b = commit!(dir, "2021-03-02", "Fix crash on nil", ["lib/a.ex", "README.md"])
    c = commit!(dir, "2022-01-10", "Bump plug", ["mix.lock"], "dependabot[bot]")

    git!(dir, ["checkout", "-q", "-b", "old-branch", a])
    g = commit!(dir, "2019-01-01", "add g", ["lib/g.ex"])
    git!(dir, ["tag", "old"])
    git!(dir, ["checkout", "-q", "main"])
    git!(dir, ["branch", "-q", "-D", "old-branch"])

    git!(dir, ["checkout", "-q", "-b", "feature", c])
    f = commit!(dir, "2024-06-01", "feature", ["lib/f.ex"])
    git!(dir, ["checkout", "-q", "main"])

    d = commit!(dir, "2025-02-01", "add CLAUDE.md", ["CLAUDE.md"])
    e = commit!(dir, "2025-03-01", "Fix race in cache", ["lib/cache.ex"])

    git!(dir, ["merge", "-q", "--no-ff", "-m", "Merge feature", "feature"], date("2025-04-01"))
    m = git!(dir, ["rev-parse", "HEAD"]) |> String.trim()
    git!(dir, ["branch", "-q", "-D", "feature"])

    h = commit!(dir, "2025-05-01", "add h", ["lib/h.ex"])

    %{dir: dir, a: a, b: b, c: c, d: d, e: e, f: f, g: g, h: h, m: m}
  end

  defp date(day) do
    stamp = day <> "T12:00:00+0000"
    [{"GIT_AUTHOR_DATE", stamp}, {"GIT_COMMITTER_DATE", stamp}]
  end

  defp commit!(dir, day, message, files, author \\ "Fulano") do
    Enum.each(files, fn file ->
      path = Path.join(dir, file)
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, "#{message}\n", [:append])
    end)

    git!(dir, ["add" | files])

    git!(
      dir,
      ["commit", "-q", "-m", message, "--author", "#{author} <#{author_email(author)}>"],
      date(day)
    )

    git!(dir, ["rev-parse", "HEAD"]) |> String.trim()
  end

  defp author_email("dependabot[bot]"), do: "49699333+dependabot[bot]@users.noreply.github.com"
  defp author_email(_), do: "fulano@example.com"

  defp git!(dir, args, env \\ []) do
    case System.cmd("git", args, cd: dir, env: env, stderr_to_stdout: true) do
      {out, 0} -> out
      {out, code} -> raise "git #{Enum.join(args, " ")} falhou (#{code}): #{out}"
    end
  end
end
