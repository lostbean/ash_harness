defmodule AshHarness.Harness.GateCheckedEventsTest do
  @moduledoc """
  v0.1.2 spec: every gate evaluation emits a `:checked` event regardless
  of pass/fail, carrying `request_id` and (where applicable) a `passed`
  boolean. Listeners can compute pass-rate metrics without span sampling.

  This file covers the four `:checked` events as a single contract:

    * `[:ash_harness, :scope, :checked]`
    * `[:ash_harness, :reasoning, :checked]`
    * `[:ash_harness, :budget, :checked]`
    * `[:ash_harness, :policy, :checked]`
  """

  use ExUnit.Case, async: false

  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Session
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  setup do
    test_pid = self()
    handler_id = "checked-events-#{System.unique_integer([:positive])}"

    events = [
      [:ash_harness, :scope, :checked],
      [:ash_harness, :reasoning, :checked],
      [:ash_harness, :budget, :checked],
      [:ash_harness, :policy, :checked],
      [:ash_harness, :scope, :violation],
      [:ash_harness, :policy, :denied]
    ]

    :telemetry.attach_many(
      handler_id,
      events,
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)
    :ok
  end

  defp ctx(opts \\ []) do
    session = struct(Session, [agent: TriageAgent, actor: %{}, request_id: "session-x"] ++ opts)
    %{ash_harness_session: session}
  end

  defp collect_checked(timeout \\ 100) do
    do_collect_checked([], timeout)
  end

  defp do_collect_checked(acc, timeout) do
    receive do
      {:telemetry, [:ash_harness, gate, :checked], m, md} ->
        do_collect_checked([{gate, m, md} | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  describe "successful dispatch" do
    test "all four :checked events fire once each with one shared :request_id" do
      # `:read` action: passes scope, reasoning not required, budget OK,
      # policy gate is mutation-only so it passes trivially. All four
      # :checked events should fire.
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())

      events = collect_checked()
      gates = Enum.map(events, fn {g, _, _} -> g end) |> Enum.sort()
      assert gates == [:budget, :policy, :reasoning, :scope]

      request_ids =
        events
        |> Enum.map(fn {_, _, md} -> md[:request_id] end)
        |> Enum.uniq()

      assert length(request_ids) == 1,
             "expected all :checked events to share one request_id, saw: #{inspect(request_ids)}"
    end

    test "scope :checked carries passed: true on success" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())
      assert_receive {:telemetry, [:ash_harness, :scope, :checked], _, %{passed: true}}
    end

    test "policy :checked carries passed: true on success" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())
      assert_receive {:telemetry, [:ash_harness, :policy, :checked], _, %{passed: true}}
    end
  end

  describe "scope failure" do
    test "still emits :scope, :checked with passed: false alongside :scope, :violation" do
      # `:destroy` is not in TriageAgent's scope.
      GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx())

      assert_receive {:telemetry, [:ash_harness, :scope, :checked], _, %{passed: false}}
      assert_receive {:telemetry, [:ash_harness, :scope, :violation], _, _}
    end

    test "subsequent gates do NOT fire after the scope refusal" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx())

      events = collect_checked()
      gates = Enum.map(events, fn {g, _, _} -> g end)
      assert :scope in gates
      refute :reasoning in gates
      refute :budget in gates
      refute :policy in gates
    end
  end

  describe "metadata shape" do
    test ":scope, :checked carries agent, resource, action, passed, request_id" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())
      assert_receive {:telemetry, [:ash_harness, :scope, :checked], _, md}

      assert md.agent == TriageAgent
      assert md.resource == Ticket
      assert md.action == :read
      assert is_boolean(md.passed)
      assert is_binary(md.request_id)
    end

    test ":reasoning, :checked carries required/present measurements" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())

      assert_receive {:telemetry, [:ash_harness, :reasoning, :checked], measurements, md}

      # :read doesn't require reasoning, so `required: false`.
      assert measurements[:required] == false
      assert is_boolean(measurements[:present])

      assert md.agent == TriageAgent
      assert is_binary(md.request_id)
    end

    test ":budget, :checked carries count/max measurements" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())
      assert_receive {:telemetry, [:ash_harness, :budget, :checked], measurements, md}

      assert is_integer(measurements[:count])
      assert is_integer(measurements[:max])
      assert is_binary(md.request_id)
    end

    test ":policy, :checked carries passed boolean and request_id" do
      GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())
      assert_receive {:telemetry, [:ash_harness, :policy, :checked], _, md}

      assert is_boolean(md.passed)
      assert is_binary(md.request_id)
    end
  end
end
