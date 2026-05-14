defmodule AshHarness.Agent.Verifiers.DelegatesUseAshHarnessAgent do
  @moduledoc """
  Every delegate target module must itself use `AshHarness.Agent`.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Delegation.DelegateEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    delegates = Verifier.get_entities(dsl_state, [:delegates_to])

    Enum.reduce_while(delegates, :ok, fn %DelegateEntry{agent_module: target}, :ok ->
      cond do
        not is_atom(target) ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:delegates_to, :delegate],
              message:
                "delegates_to entry references non-module #{inspect(target)} " <>
                  "on agent #{inspect(module)}"
            )}}

        ash_harness_agent?(target) ->
          {:cont, :ok}

        true ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:delegates_to, :delegate],
              message:
                "delegates_to entry on agent #{inspect(module)} references " <>
                  "#{inspect(target)}, which does not `use AshHarness.Agent`"
            )}}
      end
    end)
  end

  defp ash_harness_agent?(module) do
    Code.ensure_loaded?(module) and
      function_exported?(module, :__ash_harness_agent__?, 0) and
      module.__ash_harness_agent__?()
  end
end
