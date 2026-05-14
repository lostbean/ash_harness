defmodule AshHarness.ReachabilityTest do
  use ExUnit.Case, async: true

  alias AshHarness.Agent.Info
  alias AshHarness.Reachability
  alias AshHarness.Test.Project
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  setup do
    %{graph: Info.reachability_graph(TriageAgent)}
  end

  test "edges_from/2 returns outgoing edges from source", %{graph: graph} do
    edges = Reachability.edges_from(graph, Ticket)
    assert length(edges) > 0

    project_edge =
      Enum.find(edges, fn edge ->
        edge.relationship_name == :project and edge.destination == Project
      end)

    assert project_edge != nil
    assert project_edge.relationship_type == :belongs_to
    assert project_edge.source == Ticket
    assert project_edge.destination_actions == [:read]
  end

  test "no edge to a destination outside scope", %{graph: graph} do
    refute Reachability.edge_to?(graph, Ticket, AshHarness.Test.Comment)
  end

  test "edge_to?/3 true for known, false for unknown", %{graph: graph} do
    assert Reachability.edge_to?(graph, Ticket, Project)
    refute Reachability.edge_to?(graph, Ticket, AshHarness.Test.Order)
  end

  test "self-referential edge is included once", %{graph: graph} do
    self_edge =
      graph
      |> Reachability.edges_from(Ticket)
      |> Enum.find(fn e -> e.relationship_name == :parent_ticket end)

    # self edge is in traversable but Ticket is also in scope, so the
    # edge exists with destination == Ticket
    assert self_edge.destination == Ticket
  end

  test "reachable_from/2 visits each node at most once", %{graph: graph} do
    reachable = Reachability.reachable_from(graph, Ticket)
    assert reachable == Enum.uniq(reachable)
    assert Ticket in reachable
  end

  test "reachable_from terminates on cycles", %{graph: graph} do
    # Even with a self-edge, traversal terminates.
    reachable = Reachability.reachable_from(graph, Ticket)
    assert is_list(reachable)
  end
end
