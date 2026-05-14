defmodule AshHarness.Agent.Verifiers.AutoExecuteInScope do
  @moduledoc """
  Every action in `behavior.auto_execute` must appear in some scope
  entry's `actions` list.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Scope.ResourceEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    auto_execute =
      Verifier.get_option(dsl_state, [:behavior], :auto_execute, [])
      |> List.wrap()

    scoped_actions =
      dsl_state
      |> Verifier.get_entities([:scope])
      |> Enum.flat_map(fn %ResourceEntry{actions: a} -> a end)
      |> MapSet.new()

    case Enum.find(auto_execute, fn a -> not MapSet.member?(scoped_actions, a) end) do
      nil ->
        :ok

      missing ->
        {:error,
         DslError.exception(
           module: module,
           path: [:behavior, :auto_execute],
           message:
             "behavior.auto_execute lists :#{missing}, but no scope entry " <>
               "exposes that action on agent #{inspect(module)}"
         )}
    end
  end
end
