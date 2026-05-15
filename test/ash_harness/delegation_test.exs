defmodule AshHarness.DelegationTest do
  use ExUnit.Case, async: false

  alias AshHarness.Delegation
  alias AshHarness.Errors
  alias AshHarness.Harness.Session
  alias AshHarness.Test.DelegatingAgent
  alias AshHarness.Test.ReadOnlyAgent
  alias AshHarness.Test.TriageAgent

  defp session(agent) do
    %Session{agent: agent, actor: %{id: "u"}, request_id: "req"}
  end

  test "unpermitted delegation returns a DelegationNotPermitted struct" do
    assert {:error, %Errors.DelegationNotPermitted{} = err} =
             Delegation.initiate(session(DelegatingAgent), ReadOnlyAgent, "?")

    assert err.from == DelegatingAgent
    assert err.to == ReadOnlyAgent
  end

  test "permitted delegation initiation respects target list" do
    # DelegatingAgent delegates to TriageAgent. The actual run may fail
    # because there's no LLM, but we just need to confirm the permission
    # check passes (and we get a delegate-side error, not a
    # DelegationNotPermitted struct).
    result = Delegation.initiate(session(DelegatingAgent), TriageAgent, "any question")
    refute match?({:error, %Errors.DelegationNotPermitted{}}, result)
  end

  test "depth exceeded returns a DelegationDepthExceeded struct" do
    deep_session = %{
      session(DelegatingAgent)
      | metadata: %{_delegation_depth: 3}
    }

    assert {:error, %Errors.DelegationDepthExceeded{} = err} =
             Delegation.initiate(deep_session, TriageAgent, "?", max_depth: 3)

    assert err.from == DelegatingAgent
    assert err.to == TriageAgent
    assert err.depth == 3
    assert err.max_depth == 3
  end

  test "max_depth option overrides default" do
    deep_session = %{
      session(DelegatingAgent)
      | metadata: %{_delegation_depth: 1}
    }

    assert {:error, %Errors.DelegationDepthExceeded{} = err} =
             Delegation.initiate(deep_session, TriageAgent, "?", max_depth: 1)

    assert err.max_depth == 1
    assert err.depth == 1
  end
end
