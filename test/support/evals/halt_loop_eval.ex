defmodule AshHarness.Test.HaltLoopEval do
  @moduledoc false

  use AshHarness.Eval

  # Fixed UUID so the LLMStub response in
  # `runner_halt_loop_test.exs` and the scenario setup agree on which
  # ticket the agent operates on. The Runner opens its own sandbox
  # (clearing any pre-existing ETS rows), so the ticket must be
  # (re-)created inside `setup` after that wipe.
  @ticket_id "11111111-1111-1111-1111-111111111111"

  def ticket_id, do: @ticket_id

  scenario "agent halts and is approved via auto_confirm" do
    agent(AshHarness.Test.TriageAgent)

    setup fn ->
      {:ok, ticket} =
        AshHarness.Test.Ticket
        |> Ash.Changeset.for_create(:open_ticket, %{title: "T-halt-loop", priority: :medium})
        |> Ash.Changeset.force_change_attribute(:id, @ticket_id)
        |> Ash.create(authorize?: false)

      %{ticket: ticket}
    end

    prompt("Please assign the ticket to alice.")

    gate :resource_state do
      assert(:ticket, :assigned_to, fn v -> v == "alice" end)
    end
  end
end
