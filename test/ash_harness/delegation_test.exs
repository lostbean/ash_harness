defmodule AshHarness.DelegationTest do
  use ExUnit.Case, async: false

  alias AshHarness.Delegation
  alias AshHarness.Harness.Session
  alias AshHarness.Test.DelegatingAgent
  alias AshHarness.Test.ReadOnlyAgent
  alias AshHarness.Test.TriageAgent

  defp session(agent) do
    %Session{agent: agent, actor: %{id: "u"}, request_id: "req"}
  end

  test "unpermitted delegation returns :delegation_not_permitted" do
    assert {:error, :delegation_not_permitted} =
             Delegation.initiate(session(DelegatingAgent), ReadOnlyAgent, "?")
  end

  test "permitted delegation initiation respects target list" do
    # DelegatingAgent delegates to TriageAgent. The actual run may fail
    # because there's no LLM, but we just need to confirm the permission
    # check passes (and we get a delegate-side error, not
    # :delegation_not_permitted).
    result = Delegation.initiate(session(DelegatingAgent), TriageAgent, "any question")
    refute match?({:error, :delegation_not_permitted}, result)
  end

  test "depth exceeded returns :delegation_depth_exceeded" do
    deep_session = %{
      session(DelegatingAgent)
      | metadata: %{_delegation_depth: 3}
    }

    assert {:error, :delegation_depth_exceeded} =
             Delegation.initiate(deep_session, TriageAgent, "?", max_depth: 3)
  end

  test "max_depth option overrides default" do
    deep_session = %{
      session(DelegatingAgent)
      | metadata: %{_delegation_depth: 1}
    }

    assert {:error, :delegation_depth_exceeded} =
             Delegation.initiate(deep_session, TriageAgent, "?", max_depth: 1)
  end
end
