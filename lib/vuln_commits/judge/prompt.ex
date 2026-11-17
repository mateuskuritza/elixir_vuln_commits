defmodule VulnCommits.Judge.Prompt do
  alias VulnCommits.Commit
  alias VulnCommits.Git

  @max_bytes 12_000

  def version, do: System.get_env("OPENAI_PROMPT_VERSION", "v2")

  def system(version) do
    :vuln_commits
    |> Application.app_dir("priv/prompts/#{version}.md")
    |> File.read!()
  end

  def diff_for(%Commit{hash: hash, elixir_files: elixir_files}, dir) do
    diff =
      case Git.diff(dir, hash, elixir_files) do
        "" -> Git.diff(dir, hash, [])
        diff -> diff
      end

    truncate(diff, @max_bytes)
  end

  def truncate(diff, max_bytes \\ @max_bytes) do
    if byte_size(diff) <= max_bytes do
      diff
    else
      cut = diff |> binary_part(0, max_bytes) |> valid_prefix()
      cut <> "\n[... diff truncated at #{max_bytes} bytes ...]"
    end
  end

  defp valid_prefix(bin) do
    if String.valid?(bin) do
      bin
    else
      valid_prefix(binary_part(bin, 0, byte_size(bin) - 1))
    end
  end

  def user(commit, diff) do
    files = Enum.map_join(commit.files, "\n", &"- #{&1}")

    """
    Repository: #{commit.repo}
    Date: #{commit.date}
    Commit message:
    #{commit.message}

    Changed files:
    #{files}

    Diff:
    ```diff
    #{String.trim_trailing(diff)}
    ```
    """
  end

  def schema do
    %{
      "type" => "object",
      "properties" => %{
        "label" => %{"type" => "string", "enum" => ["VULNERABLE", "NEUTRAL"]},
        "cia" => %{
          "type" => "string",
          "enum" => ["confidentiality", "integrity", "availability", "none"]
        },
        "reason" => %{"type" => "string"}
      },
      "required" => ["label", "cia", "reason"],
      "additionalProperties" => false
    }
  end
end
