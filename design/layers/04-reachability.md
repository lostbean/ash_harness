# Layer 04 — Reachability

Computes the navigable graph of resources and relationships an agent can
traverse, derived from its scope and the resources' `traversable`
annotations.

## Purpose

The agent's system prompt includes a "Connections" section listing which
relationships it may traverse. The reachability graph is the input to
that rendering. It also informs progressive disclosure: when the agent
loads a resource skill, the LLM is told which other resource skills are
reachable from it.

## Definitions

An **edge** exists from resource A to resource B iff:

1. A is in the agent's scope.
2. The relationship `r` from A → B is listed in `A`'s `traversable`
   annotation. (If A is unannotated, no relationships are traversable.)
3. B is in the agent's scope.

The relationship's direction is preserved (`belongs_to`, `has_one`,
`has_many`, `many_to_many`).

## Data structure

```elixir
defmodule AshHarness.Reachability do
  @type edge :: %{
    relationship_name: atom(),
    relationship_type: :belongs_to | :has_one | :has_many | :many_to_many,
    source: module(),
    destination: module(),
    destination_actions: [atom()]
  }

  @type graph :: %{module() => [edge()]}
end
```

The graph is a map keyed by source resource. Resources with no outgoing
edges still appear (with `[]`), so callers can rely on `Map.has_key?/2`
to detect "in scope at all."

## Algorithm

```text
build(agent_module):
  scope            = AshHarness.Agent.Info.scope_entries(agent_module)
  scoped_resources = MapSet.new(scope, & &1.module)
  graph            = %{}

  for entry in scope:
    resource = entry.module
    rels     = Ash.Resource.Info.relationships(resource)
    annotated_traversable =
      if AshHarness.Resource.Info.agent_annotated?(resource),
        do: MapSet.new(AshHarness.Resource.Info.traversable(resource)),
        else: MapSet.new()        # unannotated → empty

    edges = for rel <- rels,
                MapSet.member?(annotated_traversable, rel.name),
                MapSet.member?(scoped_resources, rel.destination) do
      %{
        relationship_name: rel.name,
        relationship_type: rel.type,
        source: resource,
        destination: rel.destination,
        destination_actions:
          AshHarness.Agent.Info.scoped_actions(agent_module, rel.destination)
      }
    end

    graph = Map.put(graph, resource, edges)

  graph
```

This is computed in the `ComputeReachability` transformer at agent
compile time and persisted to DSL state under `:reachability_graph`.
At runtime, `AshHarness.Agent.Info.reachability_graph/1` reads it back
in O(1).

## Public API

```elixir
defmodule AshHarness.Reachability do
  @spec build(module()) :: graph()
  def build(agent_module)

  @spec edges_from(graph(), module()) :: [edge()]
  def edges_from(graph, source)

  @spec reachable_from(graph(), module()) :: [module()]
  # Transitive closure starting from `source`. Detects cycles.
  def reachable_from(graph, source)

  @spec edge_to?(graph(), module(), module()) :: boolean()
  def edge_to?(graph, source, destination)
end
```

`reachable_from/2` is the BFS/DFS transitive closure with a visited-set
to prevent infinite loops on cyclic graphs (Project ↔ Ticket).

## Edge cases

### Unannotated resources

A resource without `AshHarness.Resource` is treated as if its
`traversable` list is `[]`. **It can still be in scope** — the agent can
read/create/update/destroy it — but it is a leaf in the graph. No
outgoing edges.

This is conservative. To opt a relationship into traversability, you must
explicitly add the extension and list it.

### Many-to-many

Many-to-many relationships in Ash typically have a join resource. The
edge connects A → B (skipping the join) if both A and B are in scope and
the relationship is in A's `traversable`. We do **not** include the join
resource as an edge unless the join itself is in scope.

### Self-referential

A self-referential relationship (e.g., Ticket parent_ticket → Ticket) is a
self-edge in the graph. `reachable_from(graph, Ticket)` includes
`Ticket` exactly once.

### Cross-domain edges

If a Ticket in domain A has `belongs_to :customer, MyApp.Crm.Customer`
and the agent's domains include both A and B (Crm), and Customer is in
scope — edge exists. If Customer is not in scope but its domain is —
no edge (per rule 3 above).

## Rendered output

The renderer reads `edges_from(graph, resource)` for each scoped resource
and emits prose like:

```
Connections:
- project   → Project   (belongs_to)
- comments  → Comment   (has_many)
- assignee  → Member    (belongs_to)
```

For progressive disclosure, when a resource skill is loaded, the
expanded prompt also lists which other resource skills the agent might
want next.

## Why we don't render the *full* graph in the initial context

For a 12-resource scope with reasonable cross-references, the full graph
can be hundreds of edges. The initial context renders only the **edges
from each resource summary**, which is much smaller. The full
`reachable_from` traversal is computed for callers that explicitly want
it (e.g., for debugging or for the `inspect_graph` meta-tool).

## Testing strategy

- Resources with no relationships → empty edges.
- Resources with relationships, all in scope, all traversable → all
  edges present.
- Resources with relationships, some in scope, some traversable → only
  intersection.
- Self-referential resources → self-edge present, no infinite loops.
- Cyclic graphs (A↔B↔C) → `reachable_from` terminates.
- Unannotated resource → empty outgoing edges, but is in graph keys.

These are codified in `test/ash_harness/reachability_test.exs`.
