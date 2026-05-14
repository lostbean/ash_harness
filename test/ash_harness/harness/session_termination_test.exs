defmodule AshHarness.Harness.SessionTerminationTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness
  alias AshHarness.Test.TriageAgent

  test "Harness.run/3 returns {:error, :session_terminated, session} after the SessionAgent crashes" do
    session = Harness.new_session(TriageAgent)
    pid = session.metadata.session_pid

    assert is_pid(pid)
    assert Process.alive?(pid)

    # Force the SessionAgent to die abruptly. :kill is brutal — the
    # GenServer cannot trap it and Process.alive?/1 returns false.
    Process.exit(pid, :kill)

    # Give the supervisor a beat to register the death (transient
    # restart strategy means it does NOT restart).
    Process.sleep(50)
    refute Process.alive?(pid)

    # Now run/3 must observe the dead pid and short-circuit.
    assert {:error, :session_terminated, returned} = Harness.run(session, "hello")
    # The returned session should still carry the original metadata,
    # so the host can clean up or build a fresh session.
    assert returned.metadata.session_pid == pid
  end

  test "Harness.run/3 on a session without a SessionAgent pid does NOT report :session_terminated" do
    # If session.metadata.session_pid is missing entirely, run/3 should
    # NOT trip the :session_terminated branch (that's for "had one, lost
    # it" not "never had one"). It should attempt to drive the orchestrator
    # — which might fail for other reasons, but not with :session_terminated.
    session = %AshHarness.Harness.Session{
      agent: TriageAgent,
      actor: %{id: "u"},
      jido_orchestrator: nil,
      request_id: "no-pid",
      metadata: %{}
    }

    result = Harness.run(session, "hello")

    refute match?({:error, :session_terminated, _}, result),
           "expected :no_orchestrator (or similar) for a session with no pid, got: #{inspect(result)}"
  end
end
