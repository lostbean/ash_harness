defmodule AshHarness.Harness.DispatchTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness
  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Test.Project
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  defp start_session_agent(opts \\ []) do
    session = %Session{
      agent: TriageAgent,
      actor: Keyword.get(opts, :actor, %{id: "user-1"}),
      mutation_count: Keyword.get(opts, :mutation_count, 0),
      metadata: Keyword.get(opts, :metadata, %{}),
      request_id: "req-disp"
    }

    {:ok, pid} = SessionSupervisor.start_session(session)
    ExUnit.Callbacks.on_exit(fn -> SessionAgent.terminate(pid) end)
    {pid, %{session | metadata: Map.put(session.metadata, :session_pid, pid)}}
  end

  defp ctx(pid, session) do
    %{
      ash_harness_session_pid: pid,
      ash_harness_session: session,
      request_id: session.request_id
    }
  end

  describe "dispatch/5" do
    test "scope_violation surfaces as repair feedback" do
      {pid, session} = start_session_agent()

      assert {:error, msg} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Ticket,
                 :destroy,
                 %{id: "abc"},
                 ctx(pid, session)
               )

      assert msg =~ "not in scope"

      trajectory = Harness.trajectory(session)
      assert Enum.any?(trajectory, fn e -> e.result_status == :scope_violation end)
    end

    test "reasoning_required when assign called without reasoning" do
      {pid, session} = start_session_agent()

      assert {:error, msg} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Ticket,
                 :assign,
                 %{id: "abc", assigned_to: "alice"},
                 ctx(pid, session)
               )

      assert msg =~ "reasoning"

      trajectory = Harness.trajectory(session)
      assert Enum.any?(trajectory, fn e -> e.result_status == :reasoning_required end)
    end

    test "successful read returns rendered records and trajectory entry" do
      {pid, session} = start_session_agent()

      assert {:ok, %{count: 0, records: []}} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Ticket,
                 :read,
                 %{},
                 ctx(pid, session)
               )

      assert Enum.any?(Harness.trajectory(session), &(&1.result_status == :ok))
    end

    test "successful mutation bumps mutation_count and records :ok" do
      {pid, session} = start_session_agent()

      assert {:ok, %{record: _}} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Ticket,
                 :open_ticket,
                 %{title: "T-1"},
                 ctx(pid, session)
               )

      assert Harness.mutation_count(session) == 1

      trajectory = Harness.trajectory(session)
      assert Enum.any?(trajectory, &(&1.result_status == :ok))
    end

    test "failed mutation does not bump mutation_count" do
      {pid, session} = start_session_agent()

      # open_ticket requires :title; omit it to force validation failure
      assert {:error, msg} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Ticket,
                 :open_ticket,
                 %{},
                 ctx(pid, session)
               )

      assert msg =~ "Validation failed"
      assert Harness.mutation_count(session) == 0

      trajectory = Harness.trajectory(session)
      assert Enum.any?(trajectory, &(&1.result_status == :validation_failed))
    end

    test "create on Project (Ash.create direct) is independent of dispatch" do
      {pid, session} = start_session_agent()

      assert {:ok, %{count: 0, records: []}} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Project,
                 :read,
                 %{},
                 ctx(pid, session)
               )
    end

    test "budget gate halts mutating dispatch when budget is reached" do
      {pid, session} = start_session_agent(mutation_count: 5)

      assert {:error, msg} =
               GeneratedAction.dispatch(
                 TriageAgent,
                 Ticket,
                 :open_ticket,
                 %{title: "x"},
                 ctx(pid, session)
               )

      assert msg =~ "budget"

      trajectory = Harness.trajectory(session)
      assert Enum.any?(trajectory, &(&1.result_status == :budget_exceeded))
    end
  end
end
