defmodule AshHarness.TelemetryMetadataTest do
  @moduledoc """
  v0.1.2: close the metadata-drift gap on ten existing telemetry events.
  See `openspec/changes/audit-followup-v0-1-2/specs/telemetry-events/spec.md`
  for the full contract.

  This file covers the metadata-only adds (no new event names):

    * `:confirmation, :approved` — gains `respondent`, `duration_ms`
    * `:confirmation, :rejected` — gains `respondent`
    * `:policy, :denied`         — gains `ash_error_class`
    * `:action, :executed`       — gains `records_returned` (read) /
                                   `records_changed` (mutation) /
                                   `error_class`
    * `:delegation, :started`    — gains `depth`, `target_trajectory_id`,
                                   `request_id`
    * `:delegation, :ended`      — gains `depth`, `target_trajectory_id`,
                                   `request_id`
    * `:eval, :scenario, :stop`  — gains `agent`, `gates_passed`,
                                   `gates_failed`
    * `:eval, :gate, :checked`   — gains `scenario`, `passed`
    * `:eval, :report, :computed` — gains `scenario`, `observations`
  """

  use ExUnit.Case, async: false

  alias AshHarness.Delegation
  alias AshHarness.Eval.Runner
  alias AshHarness.Harness
  alias AshHarness.Harness.ConfirmationGate
  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Test.DelegatingAgent
  alias AshHarness.Test.ReadOnlyAgent
  alias AshHarness.Test.Restricted
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent
  alias Jido.Composer.HITL.ApprovalResponse

  setup do
    test_pid = self()
    handler_id = "telemetry-meta-#{System.unique_integer([:positive])}"

    events = [
      [:ash_harness, :confirmation, :approved],
      [:ash_harness, :confirmation, :rejected],
      [:ash_harness, :policy, :denied],
      [:ash_harness, :action, :executed],
      [:ash_harness, :delegation, :started],
      [:ash_harness, :delegation, :ended],
      [:ash_harness, :delegation, :denied],
      [:ash_harness, :eval, :scenario, :stop],
      [:ash_harness, :eval, :gate, :checked],
      [:ash_harness, :eval, :report, :computed]
    ]

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  describe "[:ash_harness, :action, :executed]" do
    test "successful read includes :records_returned (count) and :error_class nil" do
      session = %Session{agent: TriageAgent, actor: %{}, request_id: "r-read"}
      ctx = %{ash_harness_session: session}

      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx)

      assert_receive {:telemetry, [:ash_harness, :action, :executed], measurements, metadata}

      assert is_integer(measurements[:records_returned])
      # records_changed is nil for reads
      assert measurements[:records_changed] == nil
      assert metadata[:status] == :ok
      assert metadata[:error_class] == nil
    end

    test "successful create includes :records_changed = 1 and :records_returned nil" do
      session = %Session{agent: TriageAgent, actor: %{}, request_id: "r-create"}
      ctx = %{ash_harness_session: session}

      GeneratedAction.dispatch(TriageAgent, Ticket, :open_ticket, %{title: "x"}, ctx)

      assert_receive {:telemetry, [:ash_harness, :action, :executed], measurements, metadata}

      assert measurements[:records_changed] == 1
      assert measurements[:records_returned] == nil
      assert metadata[:status] == :ok
      assert metadata[:error_class] == nil
    end

    test "failed validation includes :error_class :validation" do
      session = %Session{agent: TriageAgent, actor: %{}, request_id: "r-fail"}
      ctx = %{ash_harness_session: session}

      # :open_ticket without :title fails Ash validation, wrapped to
      # ValidationFailed → classifies as :validation.
      GeneratedAction.dispatch(TriageAgent, Ticket, :open_ticket, %{}, ctx)

      assert_receive {:telemetry, [:ash_harness, :action, :executed], _measurements, metadata}

      assert metadata[:status] == :error
      assert metadata[:error_class] == :validation
    end
  end

  describe "[:ash_harness, :policy, :denied]" do
    test "carries :ash_error_class" do
      session = %Session{
        agent: TriageAgent,
        actor: AshHarness.Agent.Info.actor(TriageAgent),
        request_id: "r-pol"
      }

      ctx = %{ash_harness_session: session, request_id: "r-pol"}

      GeneratedAction.dispatch(TriageAgent, Restricted, :create, %{name: "x"}, ctx)

      assert_receive {:telemetry, [:ash_harness, :policy, :denied], _measurements, metadata}
      assert metadata[:ash_error_class] in [:forbidden, :unknown]
      assert is_binary(metadata[:request_id])
    end
  end

  describe "[:ash_harness, :confirmation, :approved]" do
    test "carries :respondent and a :duration_ms measurement" do
      # Drive ConfirmationGate directly with an approval entry that
      # already carries respondent + duration_ms in the metadata.
      session = %Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "r-conf",
        metadata: %{
          approvals: %{
            {Ticket, :assign} => %{
              decision: :approved,
              respondent: %{id: "alice"},
              duration_ms: 750
            }
          }
        }
      }

      intent = %Intent{
        resource: Ticket,
        action: :assign,
        input: %{},
        request_id: "r-conf"
      }

      assert :ok = ConfirmationGate.check(session, intent)

      assert_receive {:telemetry, [:ash_harness, :confirmation, :approved], measurements,
                      metadata}

      assert metadata[:respondent] == %{id: "alice"}
      assert measurements[:duration_ms] == 750
      assert metadata[:request_id] == "r-conf"
    end

    test ":respondent defaults to :unspecified when host omits it" do
      session = %Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "r-conf2",
        metadata: %{
          approvals: %{
            {Ticket, :assign} => %{decision: :approved}
          }
        }
      }

      intent = %Intent{resource: Ticket, action: :assign, input: %{}, request_id: "r-conf2"}

      assert :ok = ConfirmationGate.check(session, intent)

      assert_receive {:telemetry, [:ash_harness, :confirmation, :approved], _, metadata}

      assert metadata[:respondent] == :unspecified
    end
  end

  describe "[:ash_harness, :confirmation, :rejected]" do
    test "carries :respondent" do
      session = %Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "r-rej"
      }

      {:ok, pid} = SessionSupervisor.start_session(session)
      on_exit(fn -> SessionAgent.terminate(pid) end)
      session = %{session | metadata: Map.put(session.metadata, :session_pid, pid)}

      response = %ApprovalResponse{
        request_id: "r-rej",
        decision: :rejected,
        data: %{resource: Ticket, action: :assign},
        respondent: %{id: "bob"},
        responded_at: DateTime.utc_now()
      }

      Harness.resume(session, response)

      assert_receive {:telemetry, [:ash_harness, :confirmation, :rejected], _, metadata}

      assert metadata[:respondent] == %{id: "bob"}
    end
  end

  describe "[:ash_harness, :delegation, :started] / :ended" do
    test ":started carries :depth, :target_trajectory_id, :request_id" do
      # An unpermitted delegation produces :denied (also useful), and a
      # permitted-but-no-LLM delegation produces :started (because the
      # depth check passes) followed by either :ended :error or
      # :delegate_halted. We exercise :started here.
      session = %Session{agent: DelegatingAgent, actor: %{id: "u"}, request_id: "r-deleg"}

      Delegation.initiate(session, TriageAgent, "any question", request_id: "parent-req-1")

      assert_receive {:telemetry, [:ash_harness, :delegation, :started], _, metadata}, 500

      assert metadata[:from_agent] == DelegatingAgent
      assert metadata[:to_agent] == TriageAgent
      assert is_integer(metadata[:depth])
      assert is_binary(metadata[:target_trajectory_id])
      assert metadata[:request_id] == "parent-req-1"
    end

    test ":denied for unpermitted target carries :target_trajectory_id and :request_id" do
      session = %Session{agent: DelegatingAgent, actor: %{id: "u"}, request_id: "r-deleg-deny"}

      Delegation.initiate(session, ReadOnlyAgent, "?", request_id: "parent-req-2")

      assert_receive {:telemetry, [:ash_harness, :delegation, :denied], _, metadata}

      assert metadata[:from_agent] == DelegatingAgent
      assert metadata[:to_agent] == ReadOnlyAgent
      assert is_binary(metadata[:target_trajectory_id])
      assert metadata[:request_id] == "parent-req-2"
    end
  end

  describe "eval telemetry" do
    defmodule MetaProbeEval do
      @moduledoc false
      use AshHarness.Eval

      scenario "metadata-probe" do
        agent(nil)
        prompt("trivial")

        gate :invariant do
          true
        end

        gate :invariant do
          false
        end

        report :trajectory do
          max_actions(100)
        end
      end
    end

    test ":scenario, :stop carries :agent, :gates_passed, :gates_failed" do
      [scenario] = MetaProbeEval.scenarios()
      Runner.run(scenario)

      assert_receive {:telemetry, [:ash_harness, :eval, :scenario, :stop], _measurements,
                      metadata}

      assert Map.has_key?(metadata, :agent)
      # one gate passes, one fails
      assert metadata[:gates_passed] == 1
      assert metadata[:gates_failed] == 1
      assert metadata[:passed] == false
    end

    test ":gate, :checked carries :scenario and :passed" do
      [scenario] = MetaProbeEval.scenarios()
      Runner.run(scenario)

      # Two gates → two :checked events. Collect both.
      first =
        receive do
          {:telemetry, [:ash_harness, :eval, :gate, :checked], _, m} -> m
        after
          500 -> flunk("no :gate, :checked received")
        end

      second =
        receive do
          {:telemetry, [:ash_harness, :eval, :gate, :checked], _, m} -> m
        after
          500 -> flunk("expected a second :gate, :checked")
        end

      for m <- [first, second] do
        assert m[:scenario] == "metadata-probe"
        assert is_boolean(m[:passed])
      end

      passed_flags = Enum.map([first, second], & &1[:passed]) |> Enum.sort()
      assert passed_flags == [false, true]
    end

    test ":report, :computed carries :scenario and :observations" do
      [scenario] = MetaProbeEval.scenarios()
      Runner.run(scenario)

      assert_receive {:telemetry, [:ash_harness, :eval, :report, :computed], _, metadata}

      assert metadata[:scenario] == "metadata-probe"
      # observations is whatever the report compute returned under that
      # key (qualitative produces a list, trajectory uses %{} as the
      # fallback)
      assert Map.has_key?(metadata, :observations)
    end
  end
end
