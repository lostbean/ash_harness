defmodule Mix.Tasks.TauBench.Run do
  @shortdoc "Run the τ-bench airline scenario suite"
  @moduledoc """
  Executes every scenario in `TauBenchAirline.Scenarios` and prints a
  summary plus aggregate gate-pass-rate.

      cd benchmarks/tau_bench_airline && mix tau_bench.run
  """

  use Mix.Task

  alias AshHarness.Eval.Runner

  @impl Mix.Task
  def run(_argv) do
    Mix.Task.run("app.start")

    # ReqLLM matches cassette interactions on request headers, which
    # includes `x-api-key`. The committed cassettes ship with a scrubbed
    # placeholder value, so in replay mode we force ReqLLM to use that
    # same placeholder regardless of what the host has set. In record
    # mode the real key is needed and we leave the env var alone.
    case System.get_env("ASH_HARNESS_CASSETTE_MODE") do
      "record" -> :ok
      "bypass" -> :ok
      _ -> Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-cassette-placeholder")
    end

    results = Runner.run_all(TauBenchAirline.Scenarios)

    pass_count = Enum.count(results, & &1.passed)
    total = length(results)
    rate = if total == 0, do: 0.0, else: pass_count / total * 100

    Mix.shell().info("\nτ-bench Airline results:")

    Enum.each(results, fn r ->
      flag = if r.passed, do: "PASS", else: "FAIL"
      Mix.shell().info("  [#{flag}] #{r.scenario_name}  (#{r.duration_ms}ms)")
    end)

    Mix.shell().info(
      "\nGate-pass-rate: #{:io_lib.format(~c"~.1f", [rate])} %  " <>
        "(#{pass_count}/#{total})"
    )
  end
end
