defmodule AshHarness.Harness.GatesTest do
  use ExUnit.Case, async: true

  alias AshHarness.Harness.BudgetGate
  alias AshHarness.Harness.ConfirmationGate
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.PolicyGate
  alias AshHarness.Harness.ReasoningGate
  alias AshHarness.Harness.ScopeGate
  alias AshHarness.Harness.Session
  alias AshHarness.Test.TriageAgent

  defp session(opts \\ []) do
    %Session{
      agent: TriageAgent,
      actor: Keyword.get(opts, :actor, %{id: "user-1"}),
      mutation_count: Keyword.get(opts, :mutation_count, 0),
      metadata: Keyword.get(opts, :metadata, %{}),
      request_id: "req-test"
    }
  end

  defp intent(resource, action, opts \\ []) do
    %Intent{
      resource: resource,
      action: action,
      input: Keyword.get(opts, :input, %{}),
      reasoning: Keyword.get(opts, :reasoning),
      request_id: "req-test"
    }
  end

  describe "ScopeGate" do
    test "allows scoped action" do
      assert :ok =
               ScopeGate.check(session(), intent(AshHarness.Test.Ticket, :read))
    end

    test "rejects out-of-scope action" do
      assert {:error, :scope_violation} =
               ScopeGate.check(session(), intent(AshHarness.Test.Ticket, :destroy))
    end
  end

  describe "ReasoningGate" do
    test "passes when action doesn't require reasoning" do
      assert :ok =
               ReasoningGate.check(session(), intent(AshHarness.Test.Ticket, :read))
    end

    test "rejects when reasoning required but missing" do
      assert {:error, :reasoning_required} =
               ReasoningGate.check(session(), intent(AshHarness.Test.Ticket, :assign))
    end

    test "passes when reasoning present" do
      assert :ok =
               ReasoningGate.check(
                 session(),
                 intent(AshHarness.Test.Ticket, :assign, reasoning: "justified.")
               )
    end
  end

  describe "ConfirmationGate" do
    test "passes for actions that don't need confirmation" do
      assert :ok =
               ConfirmationGate.check(session(), intent(AshHarness.Test.Ticket, :read))
    end

    test "halts with ApprovalRequest for confirm_before actions" do
      assert {:halt, %Jido.Composer.HITL.ApprovalRequest{} = req} =
               ConfirmationGate.check(session(), intent(AshHarness.Test.Ticket, :assign))

      assert req.metadata.action == :assign
      assert :approved in req.allowed_responses
    end

    test "passes after approval is recorded" do
      approval_key = {AshHarness.Test.Ticket, :assign}
      session = session(metadata: %{approvals: %{approval_key => :approved}})

      assert :ok =
               ConfirmationGate.check(session, intent(AshHarness.Test.Ticket, :assign))
    end
  end

  describe "BudgetGate" do
    test "passes for reads regardless of count" do
      session = session(mutation_count: 99)
      assert :ok = BudgetGate.check(session, intent(AshHarness.Test.Ticket, :read))
    end

    test "passes for a mutation under the budget" do
      session = session(mutation_count: 0)

      assert :ok =
               BudgetGate.check(session, intent(AshHarness.Test.Ticket, :open_ticket))
    end

    test "rejects when budget is exhausted" do
      # TriageAgent has max_mutations_per_turn 5
      session = session(mutation_count: 5)

      assert {:error, :budget_exceeded} =
               BudgetGate.check(session, intent(AshHarness.Test.Ticket, :open_ticket))
    end
  end

  describe "PolicyGate" do
    test "passes for read actions" do
      assert :ok =
               PolicyGate.check(session(), intent(AshHarness.Test.Ticket, :read))
    end

    test "passes when Ash.can? returns truthy (test policies always allow)" do
      assert :ok =
               PolicyGate.check(
                 session(),
                 intent(AshHarness.Test.Ticket, :assign, input: %{assigned_to: "alice"})
               )
    end
  end
end
