defmodule AshHarness.Agent.Verifiers.ToolNamesUnique do
  @moduledoc """
  Refuses an agent whose scoped resources have module names that produce
  the same canonical short-name (e.g., `MyApp.Sales.Order` and
  `MyApp.Returns.Order`). Suggests adding the per-resource `as: "..."`
  alias when the conflict is detected.

  See `AshHarness.Schema.tool_name/2` for the naming rule.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Scope.ResourceEntry
  alias AshHarness.Schema
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    short_names =
      dsl_state
      |> Verifier.get_entities([:scope])
      |> Enum.filter(&match?(%ResourceEntry{}, &1))
      |> Enum.map(fn %ResourceEntry{module: m} -> {Schema.resource_short_name(m), m} end)

    duplicates =
      short_names
      |> Enum.group_by(fn {short, _} -> short end, fn {_, m} -> m end)
      |> Enum.filter(fn {_short, mods} -> length(Enum.uniq(mods)) > 1 end)

    case duplicates do
      [] ->
        :ok

      [{short, mods} | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:scope],
           message:
             "two scoped resources on agent #{inspect(module)} share the " <>
               "short name \"#{short}\": #{inspect(mods)}. " <>
               "Add `as: \"<unique>\"` to one of them to disambiguate the " <>
               "tool name."
         )}
    end
  end
end
