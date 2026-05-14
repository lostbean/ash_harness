defmodule AshHarness.Agent.Verifiers.ConfirmBeforeInScope do
  @moduledoc """
  Every action in `behavior.confirm_before` must appear in some scope
  entry's `actions` list.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Scope.ResourceEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    confirm_before =
      Verifier.get_option(dsl_state, [:behavior], :confirm_before, [])
      |> List.wrap()

    scoped_actions =
      dsl_state
      |> Verifier.get_entities([:scope])
      |> Enum.flat_map(fn %ResourceEntry{actions: a} -> a end)
      |> MapSet.new()

    case Enum.find(confirm_before, fn a -> not MapSet.member?(scoped_actions, a) end) do
      nil ->
        :ok

      missing ->
        {:error,
         DslError.exception(
           module: module,
           path: [:behavior, :confirm_before],
           message:
             "behavior.confirm_before lists :#{missing}, but no scope entry " <>
               "exposes that action on agent #{inspect(module)}"
         )}
    end
  end
end
