defmodule AshDynamo.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_dynamo,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ash, "~> 3.0"},
      {:ex_aws_dynamo, "~> 4.2"},
      {:hackney, "~> 1.25"},
      {:sourceror, "~> 1.8", only: [:dev, :test]}
    ]
  end
end
