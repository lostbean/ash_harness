defmodule AshHarness.Harness.ConfirmationResumeTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias Jido.Composer.HITL.ApprovalResponse

  describe "resume/2 fallback when no Jido suspension is pending" do
    test "records approval and returns :resumed for v0.1.0-style host replay" do
      session = %Session{
        agent: AshHarness.Test.TriageAgent,
        actor: %{id: "u"},
        request_id: "req-no-jido"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      session = %{session | metadata: Map.put(session.metadata, :session_pid, pid)}

      response = %ApprovalResponse{
        request_id: "req-no-jido",
        decision: :approved,
        data: %{
          resource: AshHarness.Test.Ticket,
          action: :assign
        },
        respondent: %{id: "human"},
        responded_at: DateTime.utc_now()
      }

      assert {:ok, :resumed, updated_session} = Harness.resume(session, response)

      key = {AshHarness.Test.Ticket, :assign}
      assert %{approvals: %{^key => :approved}} = updated_session.metadata

      held = SessionAgent.get_state(pid)
      assert %{approvals: %{^key => :approved}} = held.metadata
    end

    test "rejected response is also persisted before re-running" do
      session = %Session{
        agent: AshHarness.Test.TriageAgent,
        actor: %{id: "u"},
        request_id: "req-rej"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      session = %{session | metadata: Map.put(session.metadata, :session_pid, pid)}

      response = %ApprovalResponse{
        request_id: "req-rej",
        decision: :rejected,
        data: %{
          resource: AshHarness.Test.Ticket,
          action: :assign
        },
        responded_at: DateTime.utc_now()
      }

      assert {:ok, :resumed, updated_session} = Harness.resume(session, response)
      key = {AshHarness.Test.Ticket, :assign}
      assert %{approvals: %{^key => :rejected}} = updated_session.metadata
    end
  end
end
