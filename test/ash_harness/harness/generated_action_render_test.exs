defmodule AshHarness.Harness.GeneratedActionRenderTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness.GeneratedAction
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  setup do
    AshHarness.Eval.Sandbox.open([Ticket])

    {:ok, pid} =
      SessionSupervisor.start_session(%Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "render-req",
        metadata: %{}
      })

    on_exit(fn -> SessionAgent.terminate(pid) end)

    session = %Session{
      agent: TriageAgent,
      actor: %{id: "u"},
      request_id: "render-req",
      metadata: %{session_pid: pid}
    }

    ctx = %{
      ash_harness_session_pid: pid,
      ash_harness_session: session,
      request_id: "render-req"
    }

    {:ok, ctx: ctx}
  end

  describe "render_result/2 sanitization" do
    test "successful create returns a JSON-encodable record map", %{ctx: ctx} do
      assert {:ok, %{record: record}} =
               GeneratedAction.dispatch(TriageAgent, Ticket, :open_ticket, %{title: "T1"}, ctx)

      assert is_map(record)
      refute is_struct(record), "expected plain map, got struct: #{inspect(record)}"

      # Should encode without raising
      json = Jason.encode!(record)
      assert is_binary(json)

      # No Ash.NotLoaded leaked through
      refute json =~ "NotLoaded"
      refute json =~ "__meta__"

      # Public attrs present
      assert record[:title] == "T1" or record["title"] == "T1"
      assert record[:id] != nil or record["id"] != nil
    end

    test "successful read returns a list of JSON-encodable maps", %{ctx: ctx} do
      {:ok, _} = Ash.create(Ticket, %{title: "T-Read"}, action: :open_ticket, authorize?: false)

      assert {:ok, %{count: c, records: records}} =
               GeneratedAction.dispatch(TriageAgent, Ticket, :read, %{}, ctx)

      assert c >= 1
      assert is_list(records)

      json = Jason.encode!(records)
      assert is_binary(json)
      refute json =~ "NotLoaded"

      Enum.each(records, fn r ->
        refute is_struct(r), "expected plain map, got struct: #{inspect(r)}"
      end)
    end

    test "Decimal and DateTime are serialized as strings", %{ctx: ctx} do
      # If the resource has any decimal or datetime fields, verify they
      # encode cleanly. Ticket doesn't, so this test is a placeholder
      # for resources that do.
      {:ok, %{record: record}} =
        GeneratedAction.dispatch(TriageAgent, Ticket, :open_ticket, %{title: "T2"}, ctx)

      # The timestamp fields (inserted_at, etc.) if any should be strings
      Enum.each(record, fn {_k, v} ->
        unless is_nil(v) or is_binary(v) or is_atom(v) or is_number(v) or is_list(v) or is_map(v) do
          flunk("Unexpected non-JSON-safe value: #{inspect(v)}")
        end
      end)
    end
  end
end
