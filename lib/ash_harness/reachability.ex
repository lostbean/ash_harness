defmodule AshHarness.Reachability do
  @moduledoc """
  Computes and queries the reachability graph an agent can traverse,
  given its scope and per-resource `traversable` annotations.

  An edge `A -> B` exists iff:

    1. `A` is in the agent's scope,
    2. `A`'s `agent_annotations.traversable` includes the relationship
       name to `B`, and
    3. `B` is in the agent's scope.

  The graph is a map of `source_module => [edge_map]`. Each edge is:

      %{
        relationship_name: atom(),
        relationship_type: :belongs_to | :has_one | :has_many | :many_to_many,
        source: module(),
        destination: module(),
        destination_actions: [atom()]
      }

  Built once at agent compile time by
  `AshHarness.Agent.Transformers.ComputeReachability` and persisted on
  the agent's DSL state under `:reachability_graph`.
  """

  alias AshHarness.Agent.Scope.ResourceEntry
  alias AshHarness.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Transformer

  @type edge :: %{
          relationship_name: atom(),
          relationship_type: :belongs_to | :has_one | :has_many | :many_to_many,
          source: module(),
          destination: module(),
          destination_actions: [atom()]
        }
  @type graph :: %{module() => [edge]}

  @doc """
  Builds the reachability graph from the agent DSL state.
  """
  @spec build(map()) :: graph()
  def build(dsl_state) do
    scope_entries = Transformer.get_entities(dsl_state, [:scope])

    actions_by_resource =
      Enum.into(scope_entries, %{}, fn %ResourceEntry{module: m, actions: a} ->
        {m, a}
      end)

    scoped_resources = MapSet.new(Map.keys(actions_by_resource))

    Enum.into(scope_entries, %{}, fn %ResourceEntry{module: source} ->
      {source, edges_for(source, actions_by_resource, scoped_resources)}
    end)
  end

  defp edges_for(source, actions_by_resource, scoped_resources) do
    case Code.ensure_compiled(source) do
      {:module, _} -> :ok
      _ -> Code.ensure_loaded(source)
    end

    if ResourceInfo.agent_annotated?(source) do
      traversable = MapSet.new(ResourceInfo.traversable(source))
      relationships = relationships(source)

      relationships
      |> Enum.filter(fn rel -> MapSet.member?(traversable, rel.name) end)
      |> Enum.flat_map(fn rel ->
        destination = rel.destination

        if MapSet.member?(scoped_resources, destination) do
          [
            %{
              relationship_name: rel.name,
              relationship_type: rel.type,
              source: source,
              destination: destination,
              destination_actions: Map.get(actions_by_resource, destination, [])
            }
          ]
        else
          []
        end
      end)
    else
      []
    end
  end

  defp relationships(resource) do
    if function_exported?(Ash.Resource.Info, :relationships, 1) do
      Ash.Resource.Info.relationships(resource)
    else
      []
    end
  end

  @doc """
  Returns all outgoing edges from `source` in the given graph.
  """
  @spec edges_from(graph(), module()) :: [edge()]
  def edges_from(graph, source) when is_map(graph) do
    Map.get(graph, source, [])
  end

  @doc """
  Returns the list of modules transitively reachable from `source` via
  outgoing edges. The traversal is BFS with a visited set, so cycles
  terminate.
  """
  @spec reachable_from(graph(), module()) :: [module()]
  def reachable_from(graph, source) when is_map(graph) do
    bfs(graph, [source], MapSet.new([source]), [source])
  end

  defp bfs(_graph, [], _visited, acc), do: Enum.reverse(acc)

  defp bfs(graph, [node | rest], visited, acc) do
    next =
      graph
      |> edges_from(node)
      |> Enum.map(& &1.destination)
      |> Enum.reject(&MapSet.member?(visited, &1))

    new_visited = Enum.reduce(next, visited, &MapSet.put(&2, &1))
    new_acc = Enum.reduce(next, acc, fn n, a -> [n | a] end)

    bfs(graph, rest ++ next, new_visited, new_acc)
  end

  @doc """
  Returns `true` if any edge exists from `source` to `destination`.
  """
  @spec edge_to?(graph(), module(), module()) :: boolean()
  def edge_to?(graph, source, destination) do
    Enum.any?(edges_from(graph, source), fn edge ->
      edge.destination == destination
    end)
  end
end
