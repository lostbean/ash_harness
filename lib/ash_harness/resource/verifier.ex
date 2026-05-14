defmodule AshHarness.Resource.Verifier do
  @moduledoc """
  Verifies the agent annotations declared via `AshHarness.Resource`:

    * every `hint :foo, "..."` references an action named `:foo`;
    * every `:bar` in `traversable [...]` references a relationship;
    * every `:baz` in `hidden_attributes [...]` references an attribute.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    annotated? =
      Verifier.get_persisted(dsl_state, :ash_harness_agent_annotated?, false)

    if annotated? do
      module = Verifier.get_persisted(dsl_state, :module)

      with :ok <- verify_hints(dsl_state, module),
           :ok <- verify_traversable(dsl_state, module) do
        verify_hidden_attributes(dsl_state, module)
      end
    else
      :ok
    end
  end

  defp verify_hints(dsl_state, module) do
    hints =
      Verifier.get_persisted(dsl_state, :ash_harness_hints_by_action, %{})

    action_names =
      dsl_state
      |> Verifier.get_entities([:actions])
      |> Enum.map(& &1.name)
      |> MapSet.new()

    Enum.reduce_while(hints, :ok, fn {action_name, _text}, :ok ->
      if MapSet.member?(action_names, action_name) do
        {:cont, :ok}
      else
        {:halt,
         {:error,
          DslError.exception(
            module: module,
            path: [:agent_annotations, :hint],
            message:
              "agent_annotations hint references unknown action :#{action_name} on resource #{inspect(module)}"
          )}}
      end
    end)
  end

  defp verify_traversable(dsl_state, module) do
    traversable =
      Verifier.get_persisted(dsl_state, :ash_harness_traversable, MapSet.new())

    relationship_names =
      dsl_state
      |> Verifier.get_entities([:relationships])
      |> Enum.map(& &1.name)
      |> MapSet.new()

    bad =
      traversable
      |> MapSet.difference(relationship_names)
      |> Enum.to_list()

    case bad do
      [] ->
        :ok

      [name | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:agent_annotations, :traversable],
           message:
             "agent_annotations.traversable references unknown relationship :#{name} on resource #{inspect(module)}"
         )}
    end
  end

  defp verify_hidden_attributes(dsl_state, module) do
    hidden =
      Verifier.get_persisted(dsl_state, :ash_harness_hidden_attributes, MapSet.new())

    attribute_names =
      dsl_state
      |> Verifier.get_entities([:attributes])
      |> Enum.map(& &1.name)
      |> MapSet.new()

    bad =
      hidden
      |> MapSet.difference(attribute_names)
      |> Enum.to_list()

    case bad do
      [] ->
        :ok

      [name | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:agent_annotations, :hidden_attributes],
           message:
             "agent_annotations.hidden_attributes references unknown attribute :#{name} on resource #{inspect(module)}"
         )}
    end
  end
end
