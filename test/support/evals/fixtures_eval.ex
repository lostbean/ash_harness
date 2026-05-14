defmodule AshHarness.Test.FixturesEval do
  @moduledoc false

  use AshHarness.Eval

  scenario "always-passing gate" do
    # No agent — assertions evaluate against setup-provided context only.
    agent(nil)

    setup fn ->
      %{ticket: %{id: "t-1", assigned_to: "alice"}}
    end

    prompt("Trivial.")

    gate :resource_state do
      assert(:ticket, :assigned_to, fn x -> x != nil end)
    end

    report :trajectory do
      max_actions(8)
    end
  end

  scenario "failing gate" do
    agent(nil)

    setup fn ->
      %{ticket: %{id: "t-2", assigned_to: nil}}
    end

    prompt("Trivial.")

    gate :resource_state do
      assert(:ticket, :assigned_to, fn x -> x != nil end)
    end
  end

  scenario "invariant gate" do
    agent(nil)

    prompt("Trivial.")

    gate :invariant do
      1 + 1 == 2
    end
  end
end
