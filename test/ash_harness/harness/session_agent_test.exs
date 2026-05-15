defmodule AshHarness.Harness.SessionAgentTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Harness.TrajectoryEntry
  alias Jido.Composer.HITL.ApprovalResponse

  defp start_agent(opts \\ []) do
    session = %Session{
      agent: AshHarness.Test.TriageAgent,
      actor: %{id: "user-1"},
      request_id: "req-test",
      metadata: Keyword.get(opts, :metadata, %{})
    }

    {:ok, pid} = SessionSupervisor.start_session(session)
    on_exit_pid(pid)
    pid
  end

  defp on_exit_pid(pid) do
    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(pid), do: SessionAgent.terminate(pid)
    end)
  end

  describe "bump_mutation/1" do
    test "increments the counter monotonically" do
      pid = start_agent()
      assert 1 = SessionAgent.bump_mutation(pid)
      assert 2 = SessionAgent.bump_mutation(pid)
      assert 3 = SessionAgent.bump_mutation(pid)
      assert %Session{mutation_count: 3} = SessionAgent.get_state(pid)
    end
  end

  describe "append_trajectory/2" do
    test "prepends entries to the trajectory" do
      pid = start_agent()
      entry = %TrajectoryEntry{timestamp: DateTime.utc_now(), turn_number: 0, result_status: :ok}
      assert :ok = SessionAgent.append_trajectory(pid, entry)
      assert %Session{trajectory: [^entry]} = SessionAgent.get_state(pid)
    end
  end

  describe "bump_repair_attempt/2" do
    test "tracks attempts per {resource, action}" do
      pid = start_agent()
      key = {AshHarness.Test.Ticket, :open_ticket}
      other = {AshHarness.Test.Ticket, :assign}

      assert 1 = SessionAgent.bump_repair_attempt(pid, key)
      assert 2 = SessionAgent.bump_repair_attempt(pid, key)
      assert 1 = SessionAgent.bump_repair_attempt(pid, other)

      assert 2 = SessionAgent.repair_attempts(pid, key)
      assert 1 = SessionAgent.repair_attempts(pid, other)
    end
  end

  describe "record_approval/2" do
    test "stores approval under {resource, action} key" do
      pid = start_agent()

      response = %ApprovalResponse{
        request_id: "req-1",
        decision: :approved,
        data: %{resource: AshHarness.Test.Ticket, action: :assign},
        respondent: %{id: "human"},
        responded_at: DateTime.utc_now()
      }

      assert :ok = SessionAgent.record_approval(pid, response)
      state = SessionAgent.get_state(pid)
      key = {AshHarness.Test.Ticket, :assign}

      # v0.1.2: approvals store a richer record (decision + respondent +
      # duration_ms) rather than a bare decision atom.
      assert %{approvals: %{^key => %{decision: :approved, respondent: %{id: "human"}}}} =
               state.metadata
    end
  end

  describe "terminate/1" do
    test "stops the agent and is idempotent on a dead pid" do
      pid = start_agent()
      assert :ok = SessionAgent.terminate(pid)
      refute Process.alive?(pid)
      assert :ok = SessionAgent.terminate(pid)
      assert {:error, :session_terminated} = SessionAgent.get_state(pid)
    end
  end

  describe "concurrent access" do
    test "two processes can both bump the counter safely" do
      pid = start_agent()
      parent = self()

      bumps = 50
      workers = 2

      for _ <- 1..workers do
        spawn_link(fn ->
          for _ <- 1..bumps, do: SessionAgent.bump_mutation(pid)
          send(parent, :done)
        end)
      end

      for _ <- 1..workers, do: assert_receive(:done, 5_000)

      assert %Session{mutation_count: count} = SessionAgent.get_state(pid)
      assert count == bumps * workers
    end
  end
end
