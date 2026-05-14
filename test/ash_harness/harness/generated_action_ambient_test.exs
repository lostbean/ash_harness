defmodule AshHarness.Harness.GeneratedActionAmbientTest do
  @moduledoc """
  Unit tests for the ambient-key plumbing on generated `Jido.Action`
  modules. The Jido orchestrator strategy dispatches tool calls via
  `Jido.Exec.run(action_module, params, %{}, timeout: 0)` — a hard-coded
  empty `ctx`. So our generated `run/2` cannot rely on `ctx` carrying the
  session pid, session struct, or request_id; it must read them from the
  ambient map that `Jido.Composer.Context.to_flat_map/1` embeds under the
  reserved `Jido.Composer.Context.ambient_key()` tuple key inside
  `params`.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Eval.Sandbox
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Test.Member
  alias AshHarness.Test.Project
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  setup do
    {:ok, _handle} = Sandbox.open([Ticket, Project, Member])

    {:ok, pid} =
      SessionSupervisor.start_session(%Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        mutation_count: 0,
        request_id: "ambient-req",
        metadata: %{}
      })

    on_exit(fn -> SessionAgent.terminate(pid) end)
    {:ok, pid: pid}
  end

  test "generated action picks up session pid from ambient params", %{pid: pid} do
    action_mod =
      AshHarness.ToolGen.action_module(
        TriageAgent,
        AshHarness.Schema.canonical_for(Ticket, :read)
      )

    ambient_key = Jido.Composer.Context.ambient_key()

    params = %{
      ambient_key => %{
        ash_harness_session_pid: pid,
        ash_harness_session: nil,
        request_id: "ambient-req"
      }
    }

    # Call the action's run/2 directly with empty ctx — the same way
    # Jido.Exec.run would invoke it.
    assert {:ok, _result} = action_mod.run(params, %{})

    # The session_pid should have been read from the ambient key,
    # so the trajectory in the held session should have an :ok entry.
    held = SessionAgent.get_state(pid)

    assert Enum.any?(held.trajectory, fn entry -> entry.result_status == :ok end),
           "expected an :ok trajectory entry in the held session; got: " <>
             inspect(held.trajectory, limit: :infinity, pretty: true)
  end

  test "successful mutation through ambient ctx bumps mutation_count", %{pid: pid} do
    action_mod =
      AshHarness.ToolGen.action_module(
        TriageAgent,
        AshHarness.Schema.canonical_for(Ticket, :open_ticket)
      )

    ambient_key = Jido.Composer.Context.ambient_key()

    params = %{
      :title => "Ambient ticket",
      :priority => :medium,
      ambient_key => %{
        ash_harness_session_pid: pid,
        request_id: "ambient-mut"
      }
    }

    assert {:ok, _} = action_mod.run(params, %{})

    held = SessionAgent.get_state(pid)
    assert held.mutation_count == 1
  end
end
