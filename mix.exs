defmodule AshHarness.MixProject do
  use Mix.Project

  @version "0.1.2"
  @source_url "https://github.com/ash-project/ash_harness"

  def cli do
    [preferred_envs: [qa: :test, "qa.full": :test, bench: :dev]]
  end

  def project do
    [
      app: :ash_harness,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      dialyzer: dialyzer(),
      aliases: aliases(),
      name: "AshHarness",
      source_url: @source_url
    ]
  end

  # `mix qa` runs the four fast quality gates in order, fail-fast.
  # Dialyzer is opt-in via `mix qa.full` because its PLT build is slow.
  # `mix bench` runs the τ-bench airline replay (a capability smoke
  # check, separate from code quality).
  defp aliases do
    [
      qa: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test",
        "credo --strict"
      ],
      "qa.full": ["qa", "dialyzer"],
      bench: [&run_tau_bench/1]
    ]
  end

  defp run_tau_bench(_args) do
    {_io, status} =
      System.cmd("mix", ["tau_bench.run"],
        cd: "benchmarks/tau_bench_airline",
        into: IO.stream(:stdio, :line),
        stderr_to_stdout: true
      )

    if status != 0, do: Mix.raise("mix tau_bench.run exited with status #{status}")
  end

  defp dialyzer do
    [
      plt_add_apps: [:mix, :ex_unit],
      ignore_warnings: ".dialyzer_ignore.exs",
      flags: [:error_handling, :missing_return, :extra_return]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {AshHarness.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(:postgres), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.0"},
      {:splode, "~> 0.2"},
      {:jido_composer, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:ash_postgres, "~> 2.0", optional: true},
      {:simple_sat, "~> 0.1", only: [:dev, :test]},
      {:req_cassette, "~> 0.6", only: [:dev, :test]},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false}
    ]
  end

  defp description do
    """
    Turn Ash Framework resources into the operating layer for AI agents
    driven by jido_composer. One source of truth for what the agent can
    do (Ash actions) and what it's allowed to do (Ash policies).
    """
  end

  defp package do
    [
      name: "ash_harness",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "AshHarness",
      source_ref: "v#{@version}",
      extras: ["README.md"]
    ]
  end
end
