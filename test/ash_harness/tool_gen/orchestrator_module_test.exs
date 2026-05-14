defmodule AshHarness.ToolGen.OrchestratorModuleTest do
  use ExUnit.Case, async: true

  alias AshHarness.ToolGen.OrchestratorModule

  describe "generated orchestrator module" do
    test "TriageAgent has an Orchestrator module under AshHarness.Generated.*" do
      mod = OrchestratorModule.orchestrator_module(AshHarness.Test.TriageAgent)
      assert mod == AshHarness.Generated.AshHarness.Test.TriageAgent.Orchestrator
      assert Code.ensure_loaded?(mod)
    end

    test "the generated module exposes new/0, configure/2, query_sync/3, tool_nodes/0" do
      mod = OrchestratorModule.orchestrator_module(AshHarness.Test.TriageAgent)
      Code.ensure_loaded!(mod)

      assert function_exported?(mod, :new, 0)
      assert function_exported?(mod, :configure, 2)
      assert function_exported?(mod, :query_sync, 3)
      assert function_exported?(mod, :tool_nodes, 0)
    end

    test "tool_nodes/0 wraps confirm_before actions with requires_approval: true" do
      mod = OrchestratorModule.orchestrator_module(AshHarness.Test.TriageAgent)
      nodes = mod.tool_nodes()

      # TriageAgent.confirm_before == [:assign] → ticket.assign action module
      ticket_assign_mod =
        AshHarness.ToolGen.action_module(
          AshHarness.Test.TriageAgent,
          AshHarness.Schema.canonical_for(AshHarness.Test.Ticket, :assign)
        )

      assert Enum.any?(nodes, fn
               {^ticket_assign_mod, opts} ->
                 Keyword.get(opts, :requires_approval, false) == true

               _ ->
                 false
             end),
             "expected #{inspect(ticket_assign_mod)} to be wrapped with requires_approval: true, got: #{inspect(nodes)}"
    end

    test "tool_nodes/0 leaves non-confirm_before actions as bare modules" do
      mod = OrchestratorModule.orchestrator_module(AshHarness.Test.TriageAgent)
      nodes = mod.tool_nodes()

      ticket_read_mod =
        AshHarness.ToolGen.action_module(
          AshHarness.Test.TriageAgent,
          AshHarness.Schema.canonical_for(AshHarness.Test.Ticket, :read)
        )

      assert ticket_read_mod in nodes,
             "expected #{inspect(ticket_read_mod)} as a bare module in tool_nodes, got: #{inspect(nodes)}"
    end

    test "agent module is recoverable from the generated orchestrator" do
      mod = OrchestratorModule.orchestrator_module(AshHarness.Test.TriageAgent)
      assert mod.__agent__() == AshHarness.Test.TriageAgent
    end

    test "ReadOnlyAgent's orchestrator has no gated nodes" do
      mod = OrchestratorModule.orchestrator_module(AshHarness.Test.ReadOnlyAgent)
      nodes = mod.tool_nodes()

      # ReadOnlyAgent has no confirm_before — every node should be a bare module
      refute Enum.any?(nodes, &match?({_mod, _opts}, &1)),
             "expected no gated nodes, got: #{inspect(nodes)}"
    end
  end
end
