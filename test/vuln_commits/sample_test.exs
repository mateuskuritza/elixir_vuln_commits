# testes da amostra manual: sorteio estratificado, export, import e concordância
defmodule VulnCommits.SampleTest do
  use ExUnit.Case, async: true

  alias VulnCommits.{Commit, CSV, Sample}

  defp commit(repo, year, i) do
    %Commit{
      repo: repo,
      hash: "#{repo}-#{year}-#{String.pad_leading(Integer.to_string(i), 3, "0")}",
      year: year,
      date: Date.new!(year, 1, rem(i, 28) + 1),
      message: "fix #{i}",
      elixir_files: ["lib/a.ex"],
      period: :extended
    }
  end

  defp population do
    for repo <- ["alfa", "beta", "gama"],
        year <- [2021, 2022],
        i <- 1..20,
        do: commit(repo, year, i)
  end

  describe "pick/2" do
    test "mesma seed devolve o mesmo resultado" do
      assert Sample.pick(population(), n: 20, seed: {1, 2, 3}) ==
               Sample.pick(population(), n: 20, seed: {1, 2, 3})
    end

    test "ordem de entrada embaralhada não muda o resultado" do
      assert Sample.pick(population(), n: 20, seed: {1, 2, 3}) ==
               Sample.pick(Enum.shuffle(population()), n: 20, seed: {1, 2, 3})
    end

    test "devolve exatamente n commits" do
      assert length(Sample.pick(population(), n: 25, seed: {1, 2, 3})) == 25
    end

    test "n maior que a lista devolve todos" do
      picked = Sample.pick(population(), n: 1000, seed: {1, 2, 3})
      assert length(picked) == 120
    end

    test "resultado vem ordenado por repo, data e hash" do
      picked = Sample.pick(population(), n: 30, seed: {1, 2, 3})
      keys = Enum.map(picked, &{&1.repo, Date.to_iso8601(&1.date), &1.hash})
      assert keys == Enum.sort(keys)
    end

    test "alocação proporcional por estrato" do
      # alfa tem 30 commits, beta tem 10: com n = 8 dão 6 e 2
      pop =
        Enum.map(1..30, &commit("alfa", 2021, &1)) ++ Enum.map(1..10, &commit("beta", 2021, &1))

      picked = Sample.pick(pop, n: 8, seed: {1, 2, 3})
      counts = Enum.frequencies_by(picked, & &1.repo)
      assert counts == %{"alfa" => 6, "beta" => 2}
    end

    test "resto do arredondamento vai para os maiores restos, empate pela ordem do estrato" do
      # três estratos de 1 commit e n = 2: cada um tem resto 2/3, ficam alfa e beta
      pop = [commit("alfa", 2021, 1), commit("beta", 2021, 1), commit("gama", 2021, 1)]
      picked = Sample.pick(pop, n: 2, seed: {1, 2, 3})
      assert Enum.map(picked, & &1.repo) == ["alfa", "beta"]
    end
  end

  describe "import/1" do
    setup do
      dir = Path.join(System.tmp_dir!(), "sample_import_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf(dir) end)
      %{dir: dir}
    end

    test "aceita label sem distinção de caixa e cia opcional", %{dir: dir} do
      path = Path.join(dir, "labeled.csv")

      CSV.write(path, ~w(repo hash url date message elixir_files diff_excerpt label cia notes), [
        ["r", "h1", "u", "2021-01-01", "m", "lib/a.ex", "d", "vulnerable", "integrity", ""],
        ["r", "h2", "u", "2021-01-02", "m", "lib/a.ex", "d", "NEUTRAL", "", "dúvida"]
      ])

      assert Sample.import(path) == [
               %{hash: "h1", label: :vulnerable, cia: "integrity"},
               %{hash: "h2", label: :neutral, cia: nil}
             ]
    end

    test "label vazio ou inválido levanta erro listando os hashes", %{dir: dir} do
      path = Path.join(dir, "labeled.csv")

      CSV.write(path, ~w(repo hash url date message elixir_files diff_excerpt label cia notes), [
        ["r", "h1", "u", "2021-01-01", "m", "lib/a.ex", "d", "", "", ""],
        ["r", "h2", "u", "2021-01-02", "m", "lib/a.ex", "d", "talvez", "", ""],
        ["r", "h3", "u", "2021-01-03", "m", "lib/a.ex", "d", "NEUTRAL", "", ""]
      ])

      error = assert_raise ArgumentError, fn -> Sample.import(path) end
      assert error.message =~ "h1"
      assert error.message =~ "h2"
      refute error.message =~ "h3"
    end
  end

  describe "agreement/2" do
    test "rótulos idênticos dão kappa 1.0" do
      manual = [
        %{hash: "a", label: :vulnerable, cia: nil},
        %{hash: "b", label: :neutral, cia: nil},
        %{hash: "c", label: :neutral, cia: nil}
      ]

      model = %{
        "a" => %{votes: [], final: :vulnerable},
        "b" => %{votes: [], final: :neutral},
        "c" => %{votes: [], final: :neutral}
      }

      result = Sample.agreement(manual, model)
      assert result.kappa == 1.0
      assert result.n == 3
      assert result.confusion == %{true_pos: 1, false_pos: 0, false_neg: 0, true_neg: 2}
    end

    test "undecided do modelo conta como neutral" do
      manual = [%{hash: "a", label: :vulnerable, cia: nil}]
      model = %{"a" => %{votes: [:vulnerable, :neutral], final: :undecided}}

      result = Sample.agreement(manual, model)
      assert result.confusion == %{true_pos: 0, false_pos: 0, false_neg: 1, true_neg: 0}
    end
  end

  describe "export/3" do
    setup do
      fx = FixtureRepo.create!()
      on_exit(fn -> File.rm_rf(fx.dir) end)

      path = Path.join(fx.dir, "sample.csv")
      %{fx: fx, path: path}
    end

    test "escreve as colunas certas com label, cia e notes vazios", %{fx: fx, path: path} do
      commits = [
        %Commit{
          repo: "fixture",
          hash: fx.b,
          date: ~D[2021-03-02],
          message: "Fix crash on nil",
          elixir_files: ["lib/a.ex"]
        }
      ]

      repo_rows = [%{name: "fixture", owner_repo: "x/fixture", dir: fx.dir}]

      Sample.export(commits, repo_rows, path)

      [header_line | _] = path |> File.read!() |> String.split("\r\n")
      assert header_line == "repo,hash,url,date,message,elixir_files,diff_excerpt,label,cia,notes"

      [row] = CSV.read(path)

      assert row["url"] == "https://github.com/x/fixture/commit/#{fx.b}"
      assert row["date"] == "2021-03-02"
      assert row["elixir_files"] == "lib/a.ex"
      assert row["diff_excerpt"] =~ "Fix crash on nil"
      assert row["label"] == ""
      assert row["cia"] == ""
      assert row["notes"] == ""
    end
  end
end
