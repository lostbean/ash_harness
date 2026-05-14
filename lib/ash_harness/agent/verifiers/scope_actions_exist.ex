defmodule AshHarness.Agent.Verifiers.ScopeActionsExist do
  @moduledoc """
  Every action listed in `scope` must be declared on its resource.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Scope.ResourceEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    entries = Verifier.get_entities(dsl_state, [:scope])

    Enum.reduce_while(entries, :ok, fn %ResourceEntry{module: resource, actions: actions}, :ok ->
      action_names =
        resource
        |> Ash.Resource.Info.actions()
        |> Enum.map(& &1.name)
        |> MapSet.new()

      case Enum.find(actions, fn a -> not MapSet.member?(action_names, a) end) do
        nil ->
          {:cont, :ok}

        missing ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:scope, :resource, :actions],
              message:
                "scope on agent #{inspect(module)} declares action :#{missing} " <>
                  "for resource #{inspect(resource)}, but no such action exists " <>
                  "on the resource"
            )}}
      end
    end)
  end
end
