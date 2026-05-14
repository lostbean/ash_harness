defmodule AshHarness.TelemetryTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  setup do
    test_pid = self()

    handler_id = "test-handler-#{System.unique_integer([:positive])}"

    events = [
      [:ash_harness, :scope, :violation],
      [:ash_harness, :reasoning, :missing],
      [:ash_harness, :budget, :exceeded],
      [:ash_harness, :confirmation, :requested],
      [:ash_harness, :action, :executed],
      [:ash_harness, :repair, :feedback]
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

  defp ctx do
    session = %Session{agent: TriageAgent, actor: %{}, request_id: "req-t"}
    %{ash_harness_session: session, request_id: "req-t"}
  end

  test "scope violation emits :scope, :violation" do
    GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx())
    assert_receive {:telemetry, [:ash_harness, :scope, :violation], _, meta}
    assert meta.action == :destroy
  end

  test "reasoning gate emits :reasoning, :missing" do
    GeneratedAction.dispatch(TriageAgent, Ticket, :assign, %{}, ctx())
    assert_receive {:telemetry, [:ash_harness, :reasoning, :missing], _, _}
  end

  test "budget exhausted emits :budget, :exceeded" do
    session = %Session{
      agent: TriageAgent,
      actor: %{},
      mutation_count: 5,
      request_id: "req-b"
    }

    GeneratedAction.dispatch(
      TriageAgent,
      Ticket,
      :open_ticket,
      %{title: "x"},
      %{ash_harness_session: session, request_id: "req-b"}
    )

    assert_receive {:telemetry, [:ash_harness, :budget, :exceeded], measurements, _}
    assert measurements.count == 5
  end

  test "successful execution emits :action, :executed with :ok status" do
    GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())
    assert_receive {:telemetry, [:ash_harness, :action, :executed], measurements, meta}
    assert meta.status == :ok
    assert is_integer(measurements.duration_ms)
  end

  test "disabled telemetry suppresses events" do
    Application.put_env(:ash_harness, :telemetry, enabled: false)

    try do
      refute Telemetry.enabled?()
      GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx())
      refute_receive {:telemetry, _, _, _}, 50
    after
      Application.put_env(:ash_harness, :telemetry, enabled: true)
    end
  end
end
