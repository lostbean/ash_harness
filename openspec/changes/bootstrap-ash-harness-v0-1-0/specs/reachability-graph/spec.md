# reachability-graph — Specification

## ADDED Requirements

### Requirement: Reachability graph derivation

`AshHarness.Reachability.build/1` SHALL compute a graph of edges from
the agent's scope and resource annotations. An edge from resource A to
resource B SHALL exist if and only if (1) A is in the agent's scope,
(2) the relationship from A to B is listed in A's `traversable`
annotation, and (3) B is in the agent's scope.

#### Scenario: Edge present when all three conditions hold
- **WHEN** Ticket and Project are both in scope and Ticket's
  `traversable` includes `:project`
- **THEN** the graph contains an edge from Ticket to Project

#### Scenario: Edge absent when destination not in scope
- **WHEN** Ticket is in scope, Ticket's `traversable` includes
  `:comments`, but Comment is NOT in scope
- **THEN** the graph contains no Ticket → Comment edge

#### Scenario: Edge absent when relationship not in traversable
- **WHEN** Ticket and Audit are both in scope but Ticket's
  `traversable` does NOT include `:audit_records`
- **THEN** the graph contains no Ticket → Audit edge

#### Scenario: Unannotated source resource
- **WHEN** a scoped resource does not use the `AshHarness.Resource`
  extension
- **THEN** the resource appears in the graph keys with an empty edge
  list — no relationships are traversable

### Requirement: Edge metadata

Each edge in the graph SHALL be a map with keys
`:relationship_name` (atom), `:relationship_type` (one of
`:belongs_to`, `:has_one`, `:has_many`, `:many_to_many`), `:source`
(module), `:destination` (module), and `:destination_actions` (list of
atoms scoped on the destination).

#### Scenario: Edge contains destination actions
- **WHEN** the agent's scope grants `[:read, :assign]` on the Ticket
  resource and an edge points from Project to Ticket
- **THEN** the edge's `:destination_actions` is `[:read, :assign]`

### Requirement: Transitive reachability traversal

`AshHarness.Reachability.reachable_from/2` SHALL return the list of
modules transitively reachable from the given source via outgoing
edges. The function SHALL terminate on cyclic graphs without revisiting
nodes.

#### Scenario: Cyclic graph terminates
- **WHEN** Project has an edge to Ticket and Ticket has an edge back to
  Project
- **THEN** `reachable_from(graph, Project)` returns `[Project, Ticket]`
  (each exactly once) and does not loop

#### Scenario: Self-referential edge
- **WHEN** Ticket has a `:parent_ticket` traversable edge to itself
- **THEN** `reachable_from(graph, Ticket)` includes `Ticket` exactly
  once and terminates

### Requirement: Edge predicates

`AshHarness.Reachability.edges_from/2` SHALL return all outgoing edges
from a given source resource. `AshHarness.Reachability.edge_to?/3`
SHALL return `true` if any edge from the source to the destination
exists, `false` otherwise.

#### Scenario: edge_to? for known edge
- **WHEN** the graph contains an edge from Ticket to Project
- **THEN** `edge_to?(graph, Ticket, Project)` returns `true`

#### Scenario: edge_to? for unknown edge
- **WHEN** the graph contains no edge from Ticket to Refund
- **THEN** `edge_to?(graph, Ticket, Refund)` returns `false`
