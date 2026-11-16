defmodule VulnCommits.Judge.PromptTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Commit
  alias VulnCommits.Judge.Prompt

  defp marker(n), do: "\n[... diff truncated at #{n} bytes ...]"

  setup do
    fx = FixtureRepo.create!()
    on_exit(fn -> File.rm_rf(fx.dir) end)
    fx
  end

  test "truncate devolve o texto inteiro quando cabe" do
    assert Prompt.truncate("abc", 10) == "abc"
  end

  test "truncate corta no limite e avisa com o marcador" do
    assert Prompt.truncate(String.duplicate("a", 20), 10) ==
             String.duplicate("a", 10) <> marker(10)
  end

  test "truncate nao corta no meio de caractere multibyte" do
    # cada é ocupa 2 bytes; 3 bytes cabem so 1 caractere inteiro
    assert Prompt.truncate("ééééé", 3) == "é" <> marker(3)
  end

  test "truncate do texto grande em utf-8 continua valido" do
    big = String.duplicate("áéí§€😀 ", 5_000)
    out = Prompt.truncate(big, 12_000)

    assert String.valid?(out)
    assert String.ends_with?(out, marker(12_000))
    assert byte_size(out) <= 12_000 + byte_size(marker(12_000))
  end

  test "diff_for pega so os arquivos elixir do commit", fx do
    commit = %Commit{repo: "owner/repo", hash: fx.b, elixir_files: ["lib/a.ex"]}
    diff = Prompt.diff_for(commit, fx.dir)

    assert diff =~ "lib/a.ex"
    refute diff =~ "README"
  end

  test "diff_for cai no diff inteiro quando nao ha arquivo elixir", fx do
    commit = %Commit{repo: "owner/repo", hash: fx.b, elixir_files: []}
    diff = Prompt.diff_for(commit, fx.dir)

    assert diff =~ "README"
  end

  test "user traz repositorio, data, mensagem, arquivos e diff em bloco" do
    commit = %Commit{
      repo: "owner/repo",
      hash: "abc123",
      date: ~D[2021-03-02],
      message: "Fix crash on nil",
      files: ["README.md", "lib/a.ex"]
    }

    msg = Prompt.user(commit, "+ fix\n")

    assert msg =~ "owner/repo"
    assert msg =~ "2021-03-02"
    assert msg =~ "Fix crash on nil"
    assert msg =~ "README.md"
    assert msg =~ "lib/a.ex"
    assert msg =~ "```diff\n+ fix\n```"
  end

  test "system le o arquivo da versao e traz a definicao do artigo" do
    text = Prompt.system("v1")

    assert text =~ "A commit is VULNERABLE if its message and changes indicate"
    assert text =~ "Otherwise NEUTRAL."
  end

  test "version padrao e v2 e le OPENAI_PROMPT_VERSION" do
    System.delete_env("OPENAI_PROMPT_VERSION")
    assert Prompt.version() == "v2"

    System.put_env("OPENAI_PROMPT_VERSION", "v1")
    assert Prompt.version() == "v1"
  after
    System.delete_env("OPENAI_PROMPT_VERSION")
  end

  test "schema tem os tres campos obrigatorios e nao aceita extras" do
    schema = Prompt.schema()

    assert schema["type"] == "object"
    assert schema["required"] == ["label", "cia", "reason"]
    assert schema["additionalProperties"] == false
    assert schema["properties"]["label"]["enum"] == ["VULNERABLE", "NEUTRAL"]

    assert schema["properties"]["cia"]["enum"] ==
             ["confidentiality", "integrity", "availability", "none"]

    assert schema["properties"]["reason"]["type"] == "string"
  end
end
