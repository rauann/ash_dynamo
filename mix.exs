defmodule AshDynamo.MixProject do
  use Mix.Project

  @version "0.2.1"

  @moduledoc """
  DynamoDB data layer for Ash resources.
  """

  def project do
    [
      app: :ash_dynamo,
      version: @version,
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      description: @moduledoc,
      deps: deps(),
      docs: docs(),
      cli: cli(),
      consolidate_protocols: Mix.env() != :dev
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: "https://github.com/rauann/ash_dynamo",
      source_ref: "v#{@version}",
      extra_section: "Guides",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "documentation/topics/ash-features.md",
        "documentation/tutorials/getting-started-with-ash-dynamo.md",
        "documentation/development/testing.md",
        "documentation/dsls/DSL-AshDynamo.DataLayer.md"
      ],
      groups_for_extras: [
        Development: ~r'documentation/develoment',
        DSLs: ~r'documentation/dsls',
        Topics: ~r'documentation/topics',
        Tutorials: ~r'documentation/tutorials'
      ]
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
      {:ash, "~> 3.11"},
      {:ex_aws_dynamo, "~> 4.2"},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false, warn_if_outdated: true},
      {:hackney, "~> 1.25"},
      {:mix_test_watch, "~> 1.4", only: [:dev, :test], runtime: false},
      {:sourceror, "~> 1.8", only: [:dev, :test]}
    ]
  end

  defp cli do
    [
      "test.watch": :test
    ]
  end
end
