defmodule AshHarness.Harness.OrchestratorFactoryTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness.OrchestratorFactory
  alias AshHarness.Harness.Session
  alias AshHarness.Test.TriageAgent
  alias Jido.Agent.Strategy.State, as: StratState

  defp build_session do
    %Session{
      agent: TriageAgent,
      actor: %{id: "u"},
      model: nil,
      rendered_context: %AshHarness.RenderedContext{
        initial_text: "test",
        resource_details: %{},
        token_estimate: 0,
        warnings: []
      },
      request_id: "req-test",
      metadata: %{},
      options: []
    }
  end

  describe "build/1" do
    test "populates approval_gate.gated_node_names from confirm_before actions" do
      assert {:ok, agent} = OrchestratorFactory.build(build_session())

      strat = StratState.get(agent)
      gated = strat.approval_gate.gated_node_names

      # TriageAgent has confirm_before [:assign] over Ticket → tool name "ticket__assign"
      assert MapSet.member?(gated, "ticket__assign"),
             "expected ticket__assign in gated_node_names, got: #{inspect(MapSet.to_list(gated))}"
    end

    test "does not gate non-confirm_before actions" do
      assert {:ok, agent} = OrchestratorFactory.build(build_session())

      strat = StratState.get(agent)
      gated = strat.approval_gate.gated_node_names

      # :read and :open_ticket are auto_execute, NOT confirm_before
      refute MapSet.member?(gated, "ticket__read")
      refute MapSet.member?(gated, "ticket__open_ticket")
    end
  end
end
