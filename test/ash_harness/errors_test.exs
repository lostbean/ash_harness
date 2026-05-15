defmodule AshHarness.ErrorsTest do
  @moduledoc """
  Asserts that the seven structured error types (`ScopeViolation`,
  `PolicyDenied`, `ValidationFailed`, `MutationLimitExceeded`,
  `ReasoningRequired`, `DelegationNotPermitted`,
  `DelegationDepthExceeded`) are constructible with their documented
  fields, behave as exceptions, and classify under
  `AshHarness.Errors.classify/1` to the expected Splode class atoms.
  """

  use ExUnit.Case, async: true

  alias AshHarness.Errors

  describe "AshHarness.Errors.ScopeViolation" do
    test "exposes :agent, :resource, :action fields and is an exception" do
      err = %Errors.ScopeViolation{agent: MyAgent, resource: Ticket, action: :destroy}

      assert err.agent == MyAgent
      assert err.resource == Ticket
      assert err.action == :destroy
      assert is_exception(err)
      assert Exception.message(err) =~ "scope"
    end

    test "classifies as :scope" do
      assert Errors.classify(%Errors.ScopeViolation{}) == :scope
    end
  end

  describe "AshHarness.Errors.PolicyDenied" do
    test "exposes :agent, :resource, :action, :actor, :ash_error fields and is an exception" do
      err = %Errors.PolicyDenied{
        agent: MyAgent,
        resource: Ticket,
        action: :create,
        actor: %{id: "u-1"},
        ash_error: %Ash.Error.Forbidden{}
      }

      assert err.agent == MyAgent
      assert err.resource == Ticket
      assert err.action == :create
      assert err.actor == %{id: "u-1"}
      assert match?(%Ash.Error.Forbidden{}, err.ash_error)
      assert is_exception(err)
      assert Exception.message(err) =~ "policy"
    end

    test "classifies as :policy" do
      assert Errors.classify(%Errors.PolicyDenied{}) == :policy
    end
  end

  describe "AshHarness.Errors.ValidationFailed" do
    test "exposes :agent, :resource, :action, :ash_error fields and is an exception" do
      err = %Errors.ValidationFailed{
        agent: MyAgent,
        resource: Ticket,
        action: :open_ticket,
        ash_error: %Ash.Error.Invalid{errors: []}
      }

      assert err.agent == MyAgent
      assert err.resource == Ticket
      assert err.action == :open_ticket
      assert match?(%Ash.Error.Invalid{}, err.ash_error)
      assert is_exception(err)
      assert Exception.message(err) =~ "validation"
    end

    test "classifies as :validation" do
      assert Errors.classify(%Errors.ValidationFailed{}) == :validation
    end
  end

  describe "AshHarness.Errors.MutationLimitExceeded" do
    test "exposes :agent, :count, :max fields and is an exception" do
      err = %Errors.MutationLimitExceeded{agent: MyAgent, count: 5, max: 5}

      assert err.agent == MyAgent
      assert err.count == 5
      assert err.max == 5
      assert is_exception(err)
      assert Exception.message(err) =~ "mutation"
    end

    test "classifies as :budget" do
      assert Errors.classify(%Errors.MutationLimitExceeded{}) == :budget
    end
  end

  describe "AshHarness.Errors.ReasoningRequired" do
    test "exposes :agent, :resource, :action fields and is an exception" do
      err = %Errors.ReasoningRequired{agent: MyAgent, resource: Ticket, action: :assign}

      assert err.agent == MyAgent
      assert err.resource == Ticket
      assert err.action == :assign
      assert is_exception(err)
      assert Exception.message(err) =~ "reasoning"
    end

    test "classifies as :reasoning" do
      assert Errors.classify(%Errors.ReasoningRequired{}) == :reasoning
    end
  end

  describe "AshHarness.Errors.DelegationNotPermitted" do
    test "exposes :from, :to, :reason fields and is an exception" do
      err = %Errors.DelegationNotPermitted{from: AgentA, to: AgentB, reason: :not_permitted}

      assert err.from == AgentA
      assert err.to == AgentB
      assert err.reason == :not_permitted
      assert is_exception(err)
      assert Exception.message(err) =~ "delegation"
    end

    test "classifies as :delegation" do
      assert Errors.classify(%Errors.DelegationNotPermitted{}) == :delegation
    end
  end

  describe "AshHarness.Errors.DelegationDepthExceeded" do
    test "exposes :from, :to, :depth, :max_depth fields and is an exception" do
      err = %Errors.DelegationDepthExceeded{
        from: AgentA,
        to: AgentB,
        depth: 3,
        max_depth: 3
      }

      assert err.from == AgentA
      assert err.to == AgentB
      assert err.depth == 3
      assert err.max_depth == 3
      assert is_exception(err)
      assert Exception.message(err) =~ "depth"
    end

    test "classifies as :delegation" do
      assert Errors.classify(%Errors.DelegationDepthExceeded{}) == :delegation
    end
  end

  describe "AshHarness.Errors.classify/1" do
    test "returns an atom in the documented set" do
      classes =
        Enum.map(
          [
            %Errors.ScopeViolation{},
            %Errors.PolicyDenied{},
            %Errors.ValidationFailed{},
            %Errors.MutationLimitExceeded{},
            %Errors.ReasoningRequired{},
            %Errors.DelegationNotPermitted{},
            %Errors.DelegationDepthExceeded{}
          ],
          &Errors.classify/1
        )

      assert Enum.all?(
               classes,
               &(&1 in [:scope, :policy, :validation, :budget, :reasoning, :delegation])
             )
    end
  end
end
