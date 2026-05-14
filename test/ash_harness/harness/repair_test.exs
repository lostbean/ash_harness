defmodule AshHarness.Harness.RepairTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Repair
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor

  defp intent do
    %Intent{
      resource: AshHarness.Test.Ticket,
      action: :assign,
      input: %{assigned_to: "alice"},
      request_id: "req"
    }
  end

  describe "format_feedback/2 with validation error" do
    test "lists one bullet per field error" do
      err = %Ash.Error.Invalid{
        errors: [
          %{field: :assigned_to, message: "is required"},
          %{field: :status, message: "must be open"}
        ]
      }

      text = Repair.format_feedback(err, intent())
      assert text =~ "- assigned_to: is required"
      assert text =~ "- status: must be open"
      assert text =~ "Accepted parameters"
    end

    test "uses general: when error has no field" do
      err = %Ash.Error.Invalid{errors: [%{message: "something failed"}]}

      text = Repair.format_feedback(err)
      assert text =~ "- general: something failed"
    end
  end

  describe "format_feedback/2 with policy denial" do
    test "explains the denial" do
      err = %Ash.Error.Forbidden{}
      text = Repair.format_feedback(err, intent())
      assert text =~ "Authorization denied"
      refute text =~ "Elixir."
    end
  end

  describe "format_feedback/2 with atom reasons" do
    test ":scope_violation" do
      assert Repair.format_feedback(:scope_violation) =~ "not in scope"
    end

    test ":reasoning_required" do
      assert Repair.format_feedback(:reasoning_required) =~ "reasoning"
    end

    test ":budget_exceeded" do
      assert Repair.format_feedback(:budget_exceeded) =~ "budget"
    end

    test ":policy_denied" do
      assert Repair.format_feedback(:policy_denied) =~ "Policy denied"
    end
  end

  describe "retryable?/1" do
    test "true for validation errors" do
      assert Repair.retryable?(%Ash.Error.Invalid{})
      assert Repair.retryable?({:validation_failed, %Ash.Error.Invalid{}})
    end

    test "false for policy denial" do
      refute Repair.retryable?(%Ash.Error.Forbidden{})
      refute Repair.retryable?({:policy_denied, %Ash.Error.Forbidden{}})
    end

    test "false for scope/budget terminal errors" do
      refute Repair.retryable?(:scope_violation)
      refute Repair.retryable?(:budget_exceeded)
    end

    test "true for :reasoning_required (LLM can retry with reasoning)" do
      assert Repair.retryable?(:reasoning_required)
    end
  end

  describe "format_feedback/2 with :repair_exhausted" do
    test "explains the limit and suggests a different approach" do
      text = Repair.format_feedback(:repair_exhausted, intent())
      assert text =~ "Retry limit reached"
      assert text =~ "AshHarness.Test.Ticket.assign"
      assert text =~ "different approach"
    end

    test "still works without an intent" do
      text = Repair.format_feedback(:repair_exhausted, nil)
      assert text =~ "Retry limit reached"
    end
  end

  describe "dispatch repair cap" do
    setup do
      session = %Session{
        agent: AshHarness.Test.TriageAgent,
        actor: %{id: "u"},
        request_id: "req-rep"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      session = %{session | metadata: Map.put(session.metadata, :session_pid, pid)}

      ctx = %{
        ash_harness_session_pid: pid,
        ash_harness_session: session,
        request_id: session.request_id
      }

      {:ok, pid: pid, session: session, ctx: ctx}
    end

    test "exhausted attempts emit telemetry and return retry-limit feedback", %{
      pid: pid,
      ctx: ctx
    } do
      cap = AshHarness.Agent.Info.max_repair_loop_retries(AshHarness.Test.TriageAgent)
      key = {AshHarness.Test.Ticket, :open_ticket}
      for _ <- 1..cap, do: SessionAgent.bump_repair_attempt(pid, key)

      handler_id = "repair-exhausted-#{System.unique_integer()}"
      parent = self()

      :telemetry.attach(
        handler_id,
        [:ash_harness, :repair, :exhausted],
        fn _evt, measurements, metadata, _ ->
          send(parent, {:exhausted, measurements, metadata})
        end,
        nil
      )

      assert {:error, msg} =
               GeneratedAction.dispatch(
                 AshHarness.Test.TriageAgent,
                 AshHarness.Test.Ticket,
                 :open_ticket,
                 %{title: "x"},
                 ctx
               )

      assert msg =~ "Retry limit reached"
      assert_receive {:exhausted, _, %{action: :open_ticket, resource: AshHarness.Test.Ticket}}

      :telemetry.detach(handler_id)
    end

    test "non-retryable failures do not consume an attempt", %{pid: pid, ctx: ctx} do
      key = {AshHarness.Test.Ticket, :destroy}

      assert 0 = SessionAgent.repair_attempts(pid, key)

      for _ <- 1..3 do
        {:error, _} =
          GeneratedAction.dispatch(
            AshHarness.Test.TriageAgent,
            AshHarness.Test.Ticket,
            :destroy,
            %{id: "x"},
            ctx
          )
      end

      assert 0 = SessionAgent.repair_attempts(pid, key)
    end
  end

  describe "policy-denial does not consume repair attempts" do
    setup do
      session = %Session{
        agent: AshHarness.Test.TriageAgent,
        actor: AshHarness.Agent.Info.actor(AshHarness.Test.TriageAgent),
        request_id: "req-policy"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      ctx = %{
        ash_harness_session_pid: pid,
        ash_harness_session: %{session | metadata: %{session_pid: pid}},
        request_id: "req-policy"
      }

      {:ok, pid: pid, ctx: ctx}
    end

    test "PolicyGate refusals do not increment the repair counter", %{pid: pid, ctx: ctx} do
      key = {AshHarness.Test.Restricted, :create}

      # Set up a telemetry handler that captures any :repair, :exhausted emission.
      parent = self()
      handler_id = "policy-no-bump-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:ash_harness, :repair, :exhausted],
        fn _evt, m, md, _ -> send(parent, {:exhausted, m, md}) end,
        nil
      )

      # Dispatch 3 times — each should be refused by PolicyGate.
      for _ <- 1..3 do
        assert {:error, msg} =
                 GeneratedAction.dispatch(
                   AshHarness.Test.TriageAgent,
                   AshHarness.Test.Restricted,
                   :create,
                   %{name: "x"},
                   ctx
                 )

        assert msg =~ "Authorization denied" or msg =~ "Policy denied",
               "expected policy-denial feedback, got: #{inspect(msg)}"
      end

      # Counter is still 0 — policy denial is non-retryable.
      assert 0 = SessionAgent.repair_attempts(pid, key)

      # No :repair_exhausted telemetry fired.
      refute_receive {:exhausted, _, _}, 100

      :telemetry.detach(handler_id)
    end
  end

  describe "policy-denial feedback mentions delegation when available" do
    test "agent without delegates: feedback does not mention delegation" do
      intent = %Intent{
        resource: AshHarness.Test.Ticket,
        action: :assign,
        input: %{},
        request_id: "r",
        metadata: %{agent: AshHarness.Test.TriageAgent}
      }

      text = Repair.format_feedback(%Ash.Error.Forbidden{}, intent)
      assert text =~ "Authorization denied"
      refute text =~ "delegat"
    end

    test "agent with delegates: feedback mentions delegation" do
      intent = %Intent{
        resource: AshHarness.Test.Ticket,
        action: :assign,
        input: %{},
        request_id: "r",
        metadata: %{agent: AshHarness.Test.DelegatingAgent}
      }

      text = Repair.format_feedback(%Ash.Error.Forbidden{}, intent)
      assert text =~ "Authorization denied"
      assert text =~ "delegat"
    end
  end

  test "output never includes file paths or Elixir.Module references" do
    err = %Ash.Error.Invalid{
      errors: [%{field: :foo, message: "bad", stacktrace: "/path/file.ex:10"}]
    }

    text = Repair.format_feedback(err, intent())
    refute text =~ ~r/\.ex:\d+/
    refute text =~ "Elixir."
  end
end
