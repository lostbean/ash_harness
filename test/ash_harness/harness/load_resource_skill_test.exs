defmodule AshHarness.Harness.LoadResourceSkillTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness
  alias AshHarness.Harness.LoadResourceSkill
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.RenderedContext
  alias AshHarness.Test.TriageAgent

  describe "LoadResourceSkill.run/2" do
    test "returns the resource detail string when known" do
      rendered =
        %RenderedContext{
          initial_text: "ctx",
          token_estimate: 0,
          resource_details: %{
            ticket: "TICKET DETAIL STRING"
          },
          warnings: []
        }

      session = %Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "r",
        rendered_context: rendered
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      ambient_key = Jido.Composer.Context.ambient_key()

      params = %{
        :resource_name => "ticket",
        ambient_key => %{
          ash_harness_session_pid: pid,
          request_id: "r"
        }
      }

      assert {:ok, %{detail: "TICKET DETAIL STRING"}} = LoadResourceSkill.run(params, %{})
    end

    test "returns an error for unknown resource" do
      rendered =
        %RenderedContext{
          initial_text: "ctx",
          token_estimate: 0,
          resource_details: %{ticket: "..."},
          warnings: []
        }

      session = %Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "r",
        rendered_context: rendered
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      ambient_key = Jido.Composer.Context.ambient_key()

      params = %{
        :resource_name => "nonexistent",
        ambient_key => %{
          ash_harness_session_pid: pid,
          request_id: "r"
        }
      }

      assert {:error, msg} = LoadResourceSkill.run(params, %{})
      assert msg =~ "Unknown resource"
    end
  end

  describe "Orchestrator wiring" do
    test "load_resource_skill is in the agent's tool_nodes" do
      mod = AshHarness.ToolGen.OrchestratorModule.orchestrator_module(TriageAgent)
      nodes = mod.tool_nodes()

      assert LoadResourceSkill in Enum.map(nodes, fn
               {m, _} -> m
               m -> m
             end)
    end

    test "load_resource_skill is NOT gated by requires_approval" do
      mod = AshHarness.ToolGen.OrchestratorModule.orchestrator_module(TriageAgent)
      nodes = mod.tool_nodes()

      refute Enum.any?(nodes, fn
               {LoadResourceSkill, opts} -> Keyword.get(opts, :requires_approval, false)
               _ -> false
             end)
    end

    test "session.new_session/2 includes load_resource_skill in the orchestrator's gated set check" do
      session = Harness.new_session(TriageAgent)
      strat = Jido.Agent.Strategy.State.get(session.jido_orchestrator)

      # load_resource_skill should NOT be in gated_node_names
      refute MapSet.member?(strat.approval_gate.gated_node_names, "load_resource_skill")

      Harness.terminate(session)
    end
  end
end
