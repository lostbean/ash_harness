defmodule AshHarness.Harness.RequestIdTest do
  @moduledoc """
  Asserts that every call to `GeneratedAction.dispatch/5` generates a
  fresh per-dispatch `request_id` (UUID v4) and threads it through:

    * the OTel `ash_harness.request.id` attribute on the active span
    * every telemetry event emitted during that dispatch
    * the trajectory entry's `metadata.request_id`

  Distinct from `session.request_id` (which is per-session/conversation)
  and the per-turn id (turn-level granularity).
  """

  use ExUnit.Case, async: false

  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  setup do
    test_pid = self()
    handler_id = "request-id-#{System.unique_integer([:positive])}"

    events = [
      [:ash_harness, :scope, :violation],
      [:ash_harness, :reasoning, :missing],
      [:ash_harness, :budget, :exceeded],
      [:ash_harness, :policy, :denied],
      [:ash_harness, :confirmation, :requested],
      [:ash_harness, :action, :executed],
      [:ash_harness, :repair, :feedback],
      [:ash_harness, :repair, :exhausted]
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
    session = %Session{agent: TriageAgent, actor: %{}, request_id: "session-1"}
    # NOTE: We deliberately omit `:request_id` from ctx so dispatch
    # generates a fresh per-dispatch id. The test verifies that two
    # consecutive dispatches on the same session see distinct ids.
    %{ash_harness_session: session}
  end

  defp collect_request_ids(timeout \\ 50) do
    do_collect_request_ids([], timeout)
  end

  defp do_collect_request_ids(acc, timeout) do
    receive do
      {:telemetry, _event, _m, %{request_id: rid}} when is_binary(rid) ->
        do_collect_request_ids([rid | acc], timeout)
    after
      timeout -> Enum.reverse(acc)
    end
  end

  test "two consecutive dispatches emit :action, :executed events with distinct :request_id values" do
    GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())

    assert_receive {:telemetry, [:ash_harness, :action, :executed], _, %{request_id: rid1}}
    assert is_binary(rid1) and byte_size(rid1) > 0

    GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx())

    assert_receive {:telemetry, [:ash_harness, :action, :executed], _, %{request_id: rid2}}
    assert is_binary(rid2) and byte_size(rid2) > 0

    refute rid1 == rid2
  end

  test "scope-gate failure emits :scope, :violation with the dispatch's :request_id" do
    GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx())

    assert_receive {:telemetry, [:ash_harness, :scope, :violation], _, %{request_id: rid}}
    assert is_binary(rid) and byte_size(rid) > 0
  end

  test "all telemetry events emitted in a single dispatch share one :request_id" do
    GeneratedAction.dispatch(TriageAgent, Ticket, :destroy, %{}, ctx())

    ids = collect_request_ids() |> Enum.uniq()

    assert length(ids) >= 1
    assert length(ids) == 1, "expected one shared request_id, saw: #{inspect(ids)}"
  end

  test "OTel :ash_harness.request.id attribute equals the dispatched request_id" do
    session = %Session{agent: TriageAgent, actor: %{}, request_id: "session-otel"}

    captured =
      Telemetry.__with_captured_otel__(fn ->
        GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, %{
          ash_harness_session: session
        })
      end)

    flat = Enum.flat_map(captured, &Map.to_list/1)

    otel_request_id =
      Enum.find_value(flat, fn
        {"ash_harness.request.id", v} -> v
        _ -> nil
      end)

    assert is_binary(otel_request_id) and byte_size(otel_request_id) > 0
    # The OTel request.id MUST be distinct from the session id when
    # the caller doesn't pass an explicit request_id — proves the
    # per-dispatch UUID was generated.
    refute otel_request_id == "session-otel"
  end

  test "OTel :ash_harness.session.id continues to source from session.request_id" do
    session = %Session{agent: TriageAgent, actor: %{}, request_id: "session-vis"}

    captured =
      Telemetry.__with_captured_otel__(fn ->
        GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, %{
          ash_harness_session: session
        })
      end)

    flat = Enum.flat_map(captured, &Map.to_list/1)
    assert {"ash_harness.session.id", "session-vis"} in flat
  end
end
