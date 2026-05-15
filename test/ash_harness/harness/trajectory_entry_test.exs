defmodule AshHarness.Harness.TrajectoryEntryTest do
  use ExUnit.Case, async: true

  alias AshHarness.Harness.TrajectoryEntry

  describe "%TrajectoryEntry{}" do
    test "has a :data field defaulting to %{}" do
      entry = %TrajectoryEntry{}
      assert Map.has_key?(entry, :data)
      assert entry.data == %{}
    end

    test "delegation entry can populate :data with reply_text and target_trajectory_id" do
      entry = %TrajectoryEntry{
        timestamp: DateTime.utc_now(),
        turn_number: 0,
        intent: %{type: :delegation, target: SomeAgent, question: "hi?"},
        result_status: :ok,
        duration_ms: 12,
        data: %{
          reply_text: "the reply",
          target_trajectory_id: "ttid-1"
        }
      }

      assert entry.data.reply_text == "the reply"
      assert entry.data.target_trajectory_id == "ttid-1"
    end
  end
end
