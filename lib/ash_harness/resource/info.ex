defmodule AshHarness.Resource.Info do
  @moduledoc """
  Introspection for resources that use the `AshHarness.Resource`
  extension. All functions accept either a resource module or a Spark
  DSL state map.

  Resources that don't use the extension still answer these functions
  with safe defaults: `description/1` returns `nil`, `hints/1` returns
  `[]`, `traversable/1` and `hidden_attributes/1` return `[]`, and
  `agent_annotated?/1` returns `false`.
  """

  alias AshHarness.Resource.Hint

  @doc """
  Returns the agent-facing description for the resource, or `nil` if
  the resource does not declare one.
  """
  @spec description(module() | map()) :: String.t() | nil
  def description(resource_or_dsl) do
    if spark_dsl?(resource_or_dsl) do
      Spark.Dsl.Extension.get_opt(
        resource_or_dsl,
        [:agent_annotations],
        :description,
        nil
      )
    else
      nil
    end
  end

  @doc """
  Returns the list of relationship names the agent is allowed to traverse
  from this resource.
  """
  @spec traversable(module() | map()) :: [atom()]
  def traversable(resource_or_dsl) do
    if spark_dsl?(resource_or_dsl) do
      case Spark.Dsl.Extension.get_persisted(
             resource_or_dsl,
             :ash_harness_traversable
           ) do
        %MapSet{} = ms -> MapSet.to_list(ms)
        _ -> get_opt_list(resource_or_dsl, :traversable)
      end
    else
      []
    end
  end

  @doc """
  Returns the list of attribute names hidden from the agent.
  """
  @spec hidden_attributes(module() | map()) :: [atom()]
  def hidden_attributes(resource_or_dsl) do
    if spark_dsl?(resource_or_dsl) do
      case Spark.Dsl.Extension.get_persisted(
             resource_or_dsl,
             :ash_harness_hidden_attributes
           ) do
        %MapSet{} = ms -> MapSet.to_list(ms)
        _ -> get_opt_list(resource_or_dsl, :hidden_attributes)
      end
    else
      []
    end
  end

  @doc """
  Returns the resource's hint entities as a list of `%Hint{}` structs.
  """
  @spec hints(module() | map()) :: [Hint.t()]
  def hints(resource_or_dsl) do
    if spark_dsl?(resource_or_dsl) do
      resource_or_dsl
      |> Spark.Dsl.Extension.get_entities([:agent_annotations])
      |> Enum.filter(&match?(%Hint{}, &1))
    else
      []
    end
  end

  @doc """
  Looks up the hint text for a given action; returns `nil` if no
  matching hint is declared.
  """
  @spec hint_for(module() | map(), atom()) :: String.t() | nil
  def hint_for(resource_or_dsl, action_name) when is_atom(action_name) do
    if spark_dsl?(resource_or_dsl) do
      case Spark.Dsl.Extension.get_persisted(
             resource_or_dsl,
             :ash_harness_hints_by_action
           ) do
        %{} = map ->
          Map.get(map, action_name)

        _ ->
          Enum.find_value(hints(resource_or_dsl), fn
            %Hint{action_name: ^action_name, text: text} -> text
            _ -> nil
          end)
      end
    else
      nil
    end
  end

  @doc """
  Returns `true` when the resource declares the `agent_annotations`
  section, `false` otherwise.
  """
  @spec agent_annotated?(module() | map()) :: boolean()
  def agent_annotated?(resource_or_dsl) do
    if spark_dsl?(resource_or_dsl) do
      case Spark.Dsl.Extension.get_persisted(
             resource_or_dsl,
             :ash_harness_agent_annotated?
           ) do
        true -> true
        _ -> false
      end
    else
      false
    end
  end

  defp get_opt_list(resource_or_dsl, key) do
    case Spark.Dsl.Extension.get_opt(resource_or_dsl, [:agent_annotations], key, []) do
      list when is_list(list) -> list
      _ -> []
    end
  end

  defp spark_dsl?(map) when is_map(map), do: true

  defp spark_dsl?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0)
  end

  defp spark_dsl?(_), do: false
end
