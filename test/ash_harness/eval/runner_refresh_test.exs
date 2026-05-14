defmodule AshHarness.Eval.RunnerRefreshTest do
  @moduledoc """
  Unit tests for `AshHarness.Eval.Runner.refresh_records/1`.

  The eval runner re-reads `setup_ctx` from the data layer before running
  gates, so that a `gate :resource_state` block sees post-run state rather
  than the stale snapshot captured at setup time. This test pins down the
  contract for that helper:

    * Ash structs with an `:id` are reloaded via `Ash.get/3`.
    * Tuples of the form `{:reload, Module, id}` are reloaded the same
      way and replaced by the freshly-loaded struct.
    * Other values (plain maps, primitives, etc.) pass through unchanged.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Eval.Runner
  alias AshHarness.Eval.Sandbox
  alias AshHarness.Test.Ticket

  setup do
    {:ok, sandbox} = Sandbox.open([Ticket])
    on_exit(fn -> Sandbox.close(sandbox) end)
    :ok
  end

  defp create_ticket!(attrs) do
    Ticket
    |> Ash.Changeset.for_create(:open_ticket, attrs)
    |> Ash.create!(authorize?: false)
  end

  test "refresh_records/1 refreshes Ash structs from the data layer" do
    ticket = create_ticket!(%{title: "T-original"})

    # Simulate the agent mutating the record after setup captured it.
    {:ok, _updated} =
      ticket
      |> Ash.Changeset.for_update(:assign, %{assigned_to: "alice"})
      |> Ash.update(authorize?: false)

    # Setup ctx still holds the stale snapshot.
    stale_ctx = %{ticket: ticket}

    refreshed = Runner.refresh_records(stale_ctx)

    refute is_nil(refreshed[:ticket]), "ticket should be refreshed, not nil"

    assert refreshed[:ticket].assigned_to == "alice",
           "expected refreshed ticket to reflect DB mutation; got: " <>
             inspect(refreshed[:ticket])

    assert is_nil(ticket.assigned_to),
           "the captured pre-mutation ticket should still be unassigned"
  end

  test "refresh_records/1 supports {:reload, module, id} tuples" do
    ticket = create_ticket!(%{title: "T-tuple"})

    {:ok, _updated} =
      ticket
      |> Ash.Changeset.for_update(:assign, %{assigned_to: "bob"})
      |> Ash.update(authorize?: false)

    refreshed = Runner.refresh_records(%{ticket: {:reload, Ticket, ticket.id}})

    assert match?(%Ticket{}, refreshed[:ticket])
    assert refreshed[:ticket].assigned_to == "bob"
    assert refreshed[:ticket].id == ticket.id
  end

  test "refresh_records/1 leaves plain maps and primitives untouched" do
    placeholder = %{id: "t-1", assigned_to: nil}

    refreshed =
      Runner.refresh_records(%{
        ticket: placeholder,
        counter: 42,
        label: "hello"
      })

    assert refreshed[:ticket] == placeholder
    assert refreshed[:counter] == 42
    assert refreshed[:label] == "hello"
  end

  test "refresh_records/1 returns the stale record when the row is gone" do
    ticket = create_ticket!(%{title: "T-doomed"})
    :ok = Ash.destroy!(ticket, authorize?: false)

    refreshed = Runner.refresh_records(%{ticket: ticket})

    # Resource has been removed; fallback is the original struct.
    assert refreshed[:ticket] == ticket
  end
end
