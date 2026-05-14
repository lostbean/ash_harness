defmodule TauBenchAirline.MixProject do
  use Mix.Project

  def project do
    [
      app: :ash_harness_tau_bench,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
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
      {:ash_harness, path: "../..", override: true},
      {:ash, "~> 3.0"},
      {:jason, "~> 1.4"},
      {:simple_sat, "~> 0.1"},
      {:req_cassette, "~> 0.6"}
    ]
  end
end
