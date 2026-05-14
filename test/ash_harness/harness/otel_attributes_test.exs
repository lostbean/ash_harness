defmodule AshHarness.Harness.OtelAttributesTest do
  @moduledoc """
  Verifies that the spec-required OpenTelemetry attributes
  (`ash_harness.scope.passed`, `ash_harness.policy.passed`,
  `ash_harness.budget.count`, `ash_harness.budget.max`,
  `ash_harness.repair.attempt`, `ash_harness.session.id`,
  `ash_harness.request.id`) are set on the active span during a
  dispatch — both on the gate-pass and gate-fail paths.

  Uses `AshHarness.Telemetry.__with_captured_otel__/1`, a test-only
  hook that intercepts OTel attribute writes into a process-local
  list instead of calling the real OTel SDK.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  defp ctx(session) do
    %{ash_harness_session: session, request_id: session.request_id}
  end

  defp flatten_attrs(captured) do
    Enum.flat_map(captured, fn
      %{} = attrs -> Map.to_list(attrs)
      kv when is_list(kv) -> kv
    end)
  end

  defp keys(captured), do: captured |> flatten_attrs() |> Enum.map(fn {k, _} -> k end)

  test "successful read sets scope.passed=true, policy.passed=true, budget.count/max, session.id, request.id" do
    session = %Session{agent: TriageAgent, actor: %{}, request_id: "req-otel-ok"}

    captured =
      Telemetry.__with_captured_otel__(fn ->
        GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx(session))
      end)

    flat = flatten_attrs(captured)
    ks = keys(captured)

    assert {"ash_harness.scope.passed", true} in flat
    assert {"ash_harness.policy.passed", true} in flat
    assert "ash_harness.budget.count" in ks
    assert "ash_harness.budget.max" in ks
    assert "ash_harness.repair.attempt" in ks
    assert {"ash_harness.session.id", "req-otel-ok"} in flat
    assert {"ash_harness.request.id", "req-otel-ok"} in flat

    budget_max =
      Enum.find_value(flat, fn
        {"ash_harness.budget.max", v} -> v
        _ -> nil
      end)

    # TriageAgent in test/support has max_mutations_per_turn 5
    assert budget_max == 5
  end

  test "scope violation sets scope.passed=false and never reaches later gates" do
    session = %Session{agent: TriageAgent, actor: %{}, request_id: "req-otel-scope"}

    captured =
      Telemetry.__with_captured_otel__(fn ->
        # :destroy is not in TriageAgent's scope for Ticket
        GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx(session))
      end)

    flat = flatten_attrs(captured)
    ks = keys(captured)

    assert {"ash_harness.scope.passed", false} in flat

    # After a scope violation, later gates' .passed attrs should not
    # have been set.
    refute "ash_harness.policy.passed" in ks

    # Session/request ids are always written at dispatch entry.
    assert {"ash_harness.request.id", "req-otel-scope"} in flat
    assert {"ash_harness.session.id", "req-otel-scope"} in flat
  end

  test "budget exceeded sets scope.passed=true and budget.count/max with the offending values" do
    session = %Session{
      agent: TriageAgent,
      actor: %{},
      mutation_count: 5,
      request_id: "req-otel-budget"
    }

    captured =
      Telemetry.__with_captured_otel__(fn ->
        GeneratedAction.dispatch(TriageAgent, Ticket, :open_ticket, %{title: "x"}, ctx(session))
      end)

    flat = flatten_attrs(captured)

    assert {"ash_harness.scope.passed", true} in flat
    assert {"ash_harness.budget.count", 5} in flat
    assert {"ash_harness.budget.max", 5} in flat
  end

  test "capture hook is a no-op outside __with_captured_otel__" do
    # Sanity: when not capturing, setting attributes shouldn't raise
    # or accumulate anywhere observable from the process dictionary.
    assert :ok = Telemetry.set_otel_attribute("scope.passed", true)
    refute Process.get(:ash_harness_test_otel_capture)
  end
end
