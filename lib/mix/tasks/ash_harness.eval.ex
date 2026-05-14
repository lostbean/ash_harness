defmodule Mix.Tasks.AshHarness.Eval do
  @shortdoc "Run AshHarness eval scenarios"
  @moduledoc """
  Runs all eval modules under `test/evals/` (configurable via
  `--path`).

  Examples:

      mix ash_harness.eval
      mix ash_harness.eval --path test/evals
  """

  use Mix.Task

  alias AshHarness.Eval.Runner

  @switches [path: :string]

  @impl Mix.Task
  def run(argv) do
    Mix.Task.run("app.start")

    {opts, _} = OptionParser.parse!(argv, switches: @switches)
    path = Keyword.get(opts, :path, "test/evals")

    modules = discover_modules(path)

    if modules == [] do
      Mix.shell().info("No eval modules found in #{path}")
    else
      Enum.each(modules, fn module ->
        Mix.shell().info("\nRunning #{inspect(module)}")
        results = Runner.run_all(module)
        print_summary(module, results)
      end)
    end
  end

  defp discover_modules(path) do
    if File.dir?(path) do
      path
      |> Path.join("**/*.exs")
      |> Path.wildcard()
      |> Enum.flat_map(fn file ->
        Code.compile_file(file)
        |> Enum.map(fn {mod, _} -> mod end)
      end)
      |> Enum.uniq()
      |> Enum.filter(&exports_scenarios?/1)
    else
      []
    end
  end

  defp exports_scenarios?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :scenarios, 0)
  end

  defp print_summary(module, results) do
    passed = Enum.count(results, & &1.passed)
    total = length(results)

    Enum.each(results, fn r ->
      flag = if r.passed, do: "PASS", else: "FAIL"
      Mix.shell().info("  [#{flag}] #{r.scenario_name} (#{r.duration_ms}ms)")
    end)

    Mix.shell().info("  → #{inspect(module)}: #{passed}/#{total} scenarios passed")
  end
end
