defmodule AshHarness.Eval.Cassette do
  @moduledoc """
  Helpers for `ReqCassette` integration inside `AshHarness.Eval.Runner`.

  The runner replays LLM HTTP traffic from a cassette per scenario so
  default `mix test` is deterministic and never hits the network. The
  recording mode is controlled by the `ASH_HARNESS_CASSETTE_MODE`
  environment variable:

    * unset / `replay` (default) — fail loudly on missing cassettes
    * `record` — hit the real LLM, write missing interactions
    * `bypass` — hit the real LLM, do not write

  Cassette files live at
  `test/cassettes/<module-snake-case>/<scenario-snake-case>.json` and
  are committed to source control.
  """

  alias AshHarness.Eval

  @doc """
  Resolve the cassette file path for an eval module and scenario name.
  Relative paths are anchored at the project root via
  `File.cwd!()` (matching ReqCassette's default).
  """
  @spec cassette_path(module(), String.t()) :: String.t()
  def cassette_path(module, scenario_name) when is_atom(module) and is_binary(scenario_name) do
    module_dir = module |> Atom.to_string() |> String.replace("Elixir.", "") |> module_slug()
    name = Eval.safe_name(scenario_name)
    Path.join(["test", "cassettes", module_dir, "#{name}.json"])
  end

  @doc """
  Cassette mode resolved from the `ASH_HARNESS_CASSETTE_MODE` env var.
  Defaults to `:replay`.
  """
  @spec mode() :: :replay | :record | :bypass
  def mode do
    case System.get_env("ASH_HARNESS_CASSETTE_MODE") do
      nil -> :replay
      "" -> :replay
      "replay" -> :replay
      "record" -> :record
      "bypass" -> :bypass
      other -> raise ArgumentError, "Unknown ASH_HARNESS_CASSETTE_MODE: #{inspect(other)}"
    end
  end

  defp module_slug(name) do
    name
    |> String.replace(~r/([a-z0-9])([A-Z])/, "\\1_\\2")
    |> String.replace(".", "_")
    |> String.downcase()
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end
end
