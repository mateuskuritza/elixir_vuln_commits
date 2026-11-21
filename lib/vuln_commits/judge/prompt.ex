defmodule VulnCommits.Judge.Prompt do
  alias VulnCommits.Commit
  alias VulnCommits.Git

  @max_bytes 12_000

  def version, do: System.get_env("PROMPT_VERSION", "v2")

  def system(version) do
    path = Application.app_dir(:vuln_commits, "priv/prompts/#{version}.md")
    File.read!(path)
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
      first_bytes = binary_part(diff, 0, max_bytes)
      cut = valid_prefix(first_bytes)
      cut <> "\n[... diff truncated at #{max_bytes} bytes ...]"
    end
  end

  defp valid_prefix(text) do
    if String.valid?(text) do
      text
    else
      shorter = binary_part(text, 0, byte_size(text) - 1)
      valid_prefix(shorter)
    end
  end

  def user(commit, diff) do
    file_lines = Enum.map(commit.files, fn file -> "- #{file}" end)
    files = Enum.join(file_lines, "\n")

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
