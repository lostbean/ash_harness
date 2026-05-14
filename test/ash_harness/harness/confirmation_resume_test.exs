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

  describe "rejection telemetry" do
    test "emits [:ash_harness, :confirmation, :rejected] on rejected resume" do
      session = %Session{
        agent: AshHarness.Test.TriageAgent,
        actor: %{id: "u"},
        request_id: "req-rej-tel"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)
      session = %{session | metadata: Map.put(session.metadata, :session_pid, pid)}

      handler_id = "rejected-tel-#{System.unique_integer()}"
      parent = self()

      :telemetry.attach(
        handler_id,
        [:ash_harness, :confirmation, :rejected],
        fn _evt, measurements, metadata, _ ->
          send(parent, {:rejected, measurements, metadata})
        end,
        nil
      )

      response = %ApprovalResponse{
        request_id: "req-rej-tel",
        decision: :rejected,
        data: %{resource: AshHarness.Test.Ticket, action: :assign},
        responded_at: DateTime.utc_now()
      }

      Harness.resume(session, response)

      assert_receive {:rejected, _measurements,
                      %{
                        agent: AshHarness.Test.TriageAgent,
                        resource: AshHarness.Test.Ticket,
                        action: :assign,
                        request_id: "req-rej-tel"
                      }}

      :telemetry.detach(handler_id)
    end

    test "does NOT emit :rejected on approved resume" do
      session = %Session{
        agent: AshHarness.Test.TriageAgent,
        actor: %{id: "u"},
        request_id: "req-app-tel"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)
      session = %{session | metadata: Map.put(session.metadata, :session_pid, pid)}

      handler_id = "rejected-tel-neg-#{System.unique_integer()}"
      parent = self()

      :telemetry.attach(
        handler_id,
        [:ash_harness, :confirmation, :rejected],
        fn _, m, md, _ -> send(parent, {:rejected, m, md}) end,
        nil
      )

      response = %ApprovalResponse{
        request_id: "req-app-tel",
        decision: :approved,
        data: %{resource: AshHarness.Test.Ticket, action: :assign},
        responded_at: DateTime.utc_now()
      }

      Harness.resume(session, response)

      refute_receive {:rejected, _, _}, 100

      :telemetry.detach(handler_id)
    end
  end
end
