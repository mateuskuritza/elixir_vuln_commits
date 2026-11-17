defmodule VulnCommits.DatasetTest do
  use ExUnit.Case, async: true
  alias VulnCommits.Dataset

  @small "test/fixtures/dataset_small.csv"

  test "agrega linhas por hash e preenche rotulo humano" do
    commits = Dataset.load(@small)
    c = Enum.find(commits, &(&1.hash == "80f3194414c86754377fa74e080448cf857d4025"))
    assert c.repo == "30-days-of-elixir"
    assert c.human_label == :neutral
    assert c.files == ["13-card-deck.exs"]
    assert c.elixir_files == c.files
    assert c.date == ~D[2019-11-27]
    assert c.year == 2019
    assert c.period == :original
  end

  test "commit vulneravel junta todos os arquivos, ordenados e relativos ao repo" do
    commits = Dataset.load(@small)
    c = Enum.find(commits, &(&1.hash == "2d68e9c4d6540a200cd134661c23400d26631f75"))
    assert c.human_label == :vulnerable
    assert length(c.files) == 2
    assert c.files == Enum.sort(c.files)
    refute Enum.any?(c.files, &String.starts_with?(&1, "/"))
  end

  test "summary conta commits, vulneraveis, arquivos e repos" do
    s = Dataset.summary(Dataset.load(@small))

    assert s == %{
             commits: 25,
             vulnerable: 2,
             files: 23,
             files_in_vulnerable: 4,
             repos_with_vulnerable: 1
           }
  end

  test "per_year agrupa por ano e calcula a proporcao" do
    py = Dataset.per_year(Dataset.load(@small))
    assert py[2019] == %{commits: 6, vulnerable: 2, proportion: 33.33}
    assert py[2014] == %{commits: 6, vulnerable: 0, proportion: 0.0}
  end

  test "repo_names lista os repositorios sem repetir" do
    names = Dataset.repo_names(Dataset.load(@small))
    assert "30-days-of-elixir" in names
    assert names == Enum.uniq(names)
  end

  test "CSV.write e CSV.read fazem o caminho de ida e volta" do
    path = Path.join(System.tmp_dir!(), "csv_roundtrip_#{System.unique_integer([:positive])}.csv")
    rows = [["a", "texto, com \"aspas\"\ne quebra"], ["b", ""]]
    VulnCommits.CSV.write(path, ["id", "txt"], rows)

    assert VulnCommits.CSV.read(path) == [
             %{"id" => "a", "txt" => "texto, com \"aspas\"\ne quebra"},
             %{"id" => "b", "txt" => ""}
           ]

    File.rm!(path)
  end

  test "dataset completo reproduz os numeros do artigo" do
    path = "data/figshare/ELIXIR_FINAL_SECURITY_BUG_DATASET.csv"

    if File.exists?(path) do
      commits = Dataset.load(path)

      assert Dataset.summary(commits) ==
               %{
                 commits: 4446,
                 vulnerable: 90,
                 files: 1769,
                 files_in_vulnerable: 319,
                 repos_with_vulnerable: 9
               }

      assert Dataset.per_year(commits)[2020].proportion == 3.86
    end
  end
end
