defmodule VulnCommits.KeywordsTest do
  use ExUnit.Case, async: true

  alias VulnCommits.Keywords

  test "lista do artigo tem 48 termos" do
    assert length(Keywords.terms()) == 48
    assert "gain access" in Keywords.terms()
  end

  test "normalize minusculiza e colapsa separadores" do
    assert Keywords.normalize("Fix  Crash: NIL!!") == "fix crash nil"
  end

  test "normalize descarta bytes invalidos" do
    assert Keywords.normalize(<<"fix ", 0xFF, "crash">>) == "fix crash"
  end

  test "casa por token com sufixo" do
    assert Keywords.match("Fix crashes when nil") == ["crash"]
    assert Keywords.match("improve permissions module") == ["permission"]
    assert Keywords.match("violates the contract") == ["violate"]
    assert Keywords.match("fix style violations") == ["violate"]
    assert Keywords.match("list vulnerabilities") == ["vulnerability"]
    assert Keywords.match("crashed twice") == ["crash"]
  end

  test "nao casa so por prefixo" do
    assert Keywords.match("ran the formatter") == []
    assert Keywords.match("rename holder") == []
    assert Keywords.match("print stacktrace") == []
  end

  test "casos simples" do
    assert Keywords.match("Fix race condition in Task") == ["race"]
    assert Keywords.match("add CSRF protection") == ["csrf"]
    assert Keywords.match("Update docs") == []
    assert Keywords.match("updated README") == []
  end

  test "termo composto casa como tokens adjacentes" do
    assert Keywords.match("gain  access to repo") == ["gain access"]
    assert Keywords.match("gain the access") == []
  end

  test "denial of service nao casa (o termo do artigo e denial service)" do
    assert Keywords.match("denial of service") == []
  end

  test "bytes invalidos na mensagem" do
    assert Keywords.match(<<"fix crash ", 0xFF>>) == ["crash"]
  end

  test "match na ordem de terms/0 e sem repeticao" do
    assert Keywords.match("crash crash and race") == ["race", "crash"]
  end

  test "radical comum nao casa com termo parecido (hole, format)" do
    assert Keywords.match("hold the lock") == []
    assert Keywords.match("holy cow") == []
    assert Keywords.match("code formation") == []
  end

  test "racy nao vira race e race nao vira racy" do
    assert Keywords.match("fix racy code") == ["racy"]
    assert Keywords.match("racing condition") == ["race"]
  end

  test "sufixos de e e y final" do
    assert Keywords.match("violating rules") == ["violate"]
    assert Keywords.match("exposing secrets") == ["expose"]
    assert Keywords.match("crashes") == ["crash"]
  end

  test "hit?" do
    refute Keywords.hit?("nothing here")
    assert Keywords.hit?("fix crash")
  end
end
