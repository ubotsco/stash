defmodule Stash.MixProject do
  use Mix.Project

  def project do
    [
      app: :stash,
      version: "0.1.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      preferred_cli_env: preferred_cli_env(),
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:redix, "~> 1.0"},
      {:con_cache, "~> 1.0"},

      # Dev & Test
      {:mix_test_watch, "~> 1.0", only: :test, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false}
    ]
  end

  defp preferred_cli_env do
    [
      test: :test,
      "test.watch": :test
    ]
  end
end
