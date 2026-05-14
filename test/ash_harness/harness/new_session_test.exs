defmodule AshHarness.Harness.NewSessionTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Test.TriageAgent

  test "new_session/2 returns a session with a live SessionAgent pid in metadata" do
    session = Harness.new_session(TriageAgent)

    pid = session.metadata.session_pid
    assert is_pid(pid), "expected metadata.session_pid to be a pid, got: #{inspect(pid)}"
    assert Process.alive?(pid)

    assert %Session{} = held = SessionAgent.get_state(pid)
    assert held.agent == TriageAgent

    Harness.terminate(session)
  end

  test "new_session/2 returns distinct pids for distinct sessions" do
    s1 = Harness.new_session(TriageAgent)
    s2 = Harness.new_session(TriageAgent)

    refute s1.metadata.session_pid == s2.metadata.session_pid

    Harness.terminate(s1)
    Harness.terminate(s2)
  end

  test "Harness.terminate/1 stops the SessionAgent" do
    session = Harness.new_session(TriageAgent)
    pid = session.metadata.session_pid

    assert Process.alive?(pid)
    assert :ok = Harness.terminate(session)
    # Brief beat for the supervisor to clean up
    Process.sleep(20)
    refute Process.alive?(pid)
  end

  test "actor and model can be overridden via opts" do
    custom_actor = %{id: "custom", role: :admin}

    session =
      Harness.new_session(TriageAgent,
        actor: custom_actor,
        model: "anthropic:claude-haiku-4-5-20251001"
      )

    assert session.actor == custom_actor
    assert session.model == "anthropic:claude-haiku-4-5-20251001"

    held = SessionAgent.get_state(session.metadata.session_pid)
    assert held.actor == custom_actor
    assert held.model == "anthropic:claude-haiku-4-5-20251001"

    Harness.terminate(session)
  end
end
