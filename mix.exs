defmodule VulnCommits.MixProject do
  use Mix.Project

  def project do
    [
      app: :vuln_commits,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.7.5"},
      {:nimble_csv, "~> 1.3"},
      {:plug, "~> 1.0", only: :test}
    ]
  end
end
