defmodule AshHarness.Agent.Verifiers.ReasoningActionsInScope do
  @moduledoc """
  Every action in `constraints.require_reasoning_for` must appear in
  some scope entry's `actions` list.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Scope.ResourceEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    require_reasoning_for =
      Verifier.get_option(dsl_state, [:constraints], :require_reasoning_for, [])
      |> List.wrap()

    scoped_actions =
      dsl_state
      |> Verifier.get_entities([:scope])
      |> Enum.flat_map(fn %ResourceEntry{actions: a} -> a end)
      |> MapSet.new()

    case Enum.find(require_reasoning_for, fn a ->
           not MapSet.member?(scoped_actions, a)
         end) do
      nil ->
        :ok

      missing ->
        {:error,
         DslError.exception(
           module: module,
           path: [:constraints, :require_reasoning_for],
           message:
             "constraints.require_reasoning_for lists :#{missing}, but no " <>
               "scope entry exposes that action on agent #{inspect(module)}"
         )}
    end
  end
end
