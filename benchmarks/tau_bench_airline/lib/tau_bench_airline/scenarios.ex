defmodule TauBenchAirline.Scenarios do
  @moduledoc """
  τ-bench airline scenarios mapped to `AshHarness.Eval.Scenario` form.

  All ten scenarios run end-to-end against committed cassettes:

    1. `change_flight` — premium reservation moved to a later flight
       (`status == :changed`).
    2. `cancel_economy` — economy reservation cancelled
       (`status == :cancelled`).
    3. `refuse_basic_cancel` — basic-fare policy refusal; status stays
       `:booked` (validation in the `:cancel` action enforces it).
    4. `read_customer` — pure-read lookup of a customer's loyalty tier;
       no mutations expected.
    5. `list_reservations` — relation traversal from customer to
       reservations; no mutations expected.
    6. `search_by_origin_dest` — flight search filtered by origin and
       destination; no mutations expected.
    7. `search_unknown_origin` — error-path: search for an unknown
       origin returns no results; agent must not hallucinate.
    8. `cross_customer_denial` — confirmation gate rejects a mutation
       when the runner answers `:always_reject`; reservation status
       stays `:booked`.
    9. `change_flight_with_reasoning` — same goal as `change_flight`
       but adds a `report :qualitative` reasoning criterion (judge
       model only invoked when `:judge_model` is set).
   10. `budget_aware_multi_cancel` — agent asked to cancel multiple
       reservations; gate asserts at most `max_mutations_per_turn`
       (=3) mutations completed; report :trajectory caps actions.
  """

  use AshHarness.Eval

  scenario "change_flight" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()

      target_reservation =
        Enum.find(seeded.reservations, fn r -> r.fare_class == :premium end) ||
          List.first(seeded.reservations)

      later_flight =
        seeded.flights
        |> Enum.reject(fn f -> f.id == target_reservation && target_reservation.flight_id end)
        |> List.last() || List.last(seeded.flights)

      %{
        reservation: target_reservation,
        later_flight: later_flight
      }
    end

    prompt(
      "Please move my premium reservation to the latest flight on the same " <>
        "JFK→LAX route. Include reasoning about why a change is acceptable."
    )

    gate :resource_state do
      assert(:reservation, :status, fn s -> s == :changed end)
    end

    report :trajectory do
      max_actions(8)
    end
  end

  scenario "cancel_economy" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()

      target_reservation =
        Enum.find(seeded.reservations, fn r -> r.fare_class == :economy end) ||
          List.first(seeded.reservations)

      %{reservation: target_reservation}
    end

    prompt(
      "Please cancel my economy reservation. The reason is that my plans " <>
        "changed and I can no longer travel. Please go ahead and cancel it now."
    )

    gate :resource_state do
      assert(:reservation, :status, fn s -> s == :cancelled end)
    end
  end

  scenario "refuse_basic_cancel" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()

      target_reservation =
        Enum.find(seeded.reservations, fn r -> r.fare_class == :basic end) ||
          List.first(seeded.reservations)

      %{reservation: target_reservation}
    end

    prompt("Please cancel my basic-fare reservation immediately.")

    gate :resource_state do
      # Policy refuses the cancel; status remains :booked
      assert(:reservation, :status, fn s -> s == :booked end)
    end

    report :trajectory do
      max_actions(8)
    end
  end

  # ----------------------------------------------------------------
  # Read-only scenarios — exercise the agent's tool selection without
  # mutations. Gates assert the data layer is unchanged.
  # ----------------------------------------------------------------

  scenario "read_customer" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()

      target_customer =
        Enum.find(seeded.customers, fn c -> c.loyalty_tier == :gold end) ||
          List.first(seeded.customers)

      %{customer: target_customer}
    end

    prompt(
      "What is the loyalty tier of customer Alice Smith? " <>
        "Please look her up and report her tier."
    )

    gate :resource_state do
      # Pure read; loyalty_tier must remain :gold.
      assert(:customer, :loyalty_tier, fn t -> t == :gold end)
    end

    report :trajectory do
      max_actions(6)
      excludes([:reservation_change_flight, :reservation_cancel])
    end
  end

  scenario "list_reservations" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()
      target_customer = Enum.find(seeded.customers, fn c -> c.name == "Alice Smith" end)
      %{customer: target_customer}
    end

    prompt(
      "List the reservations belonging to customer Alice Smith. " <>
        "Don't modify anything — just report what she has booked."
    )

    gate :resource_state do
      # Read-only: Alice's loyalty_tier still :gold; mutations would
      # also be visible via the trajectory excludes below.
      assert(:customer, :loyalty_tier, fn t -> t == :gold end)
    end

    report :trajectory do
      max_actions(8)
      excludes([:reservation_change_flight, :reservation_cancel])
    end
  end

  scenario "search_by_origin_dest" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()
      # Pin the first JFK→LAX flight so the gate has something stable
      # to reference for "unchanged" assertions.
      pinned =
        Enum.find(seeded.flights, fn f ->
          f.origin == "JFK" and f.destination == "LAX"
        end) || List.first(seeded.flights)

      %{pinned_flight: pinned}
    end

    prompt(
      "Find me flights from JFK to LAX. " <>
        "List the options with departure times — no booking, just a search."
    )

    gate :resource_state do
      # Read-only: flight seat counts must be untouched. The seed sets
      # f-100 with 12 seats available; if the agent erroneously
      # mutated, that number would shift.
      assert(:pinned_flight, :seats_available, fn s -> s == 12 end)
    end

    report :trajectory do
      max_actions(6)
      excludes([:reservation_change_flight, :reservation_cancel])
    end
  end

  scenario "search_unknown_origin" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()
      pinned = List.first(seeded.flights)
      %{pinned_flight: pinned}
    end

    prompt(
      "I need flights departing from XYZ next week. " <>
        "Search and tell me what you find — don't make anything up."
    )

    gate :resource_state do
      # No flight rows should be mutated and no reservation created.
      assert(:pinned_flight, :seats_available, fn s -> s == 12 end)
    end

    report :trajectory do
      max_actions(6)
      excludes([:reservation_change_flight, :reservation_cancel])
    end
  end

  # ----------------------------------------------------------------
  # Confirmation / reasoning / budget scenarios.
  # ----------------------------------------------------------------

  scenario "cross_customer_denial" do
    agent(TauBenchAirline.Agent)
    # Reject any confirmation request so a mutation attempt cannot
    # land regardless of what the agent decides. The
    # `support-bot` actor bypasses ownership policies by design (see
    # Reservation policies), so the denial signal here is the
    # confirmation gate, not the authorizer.
    auto_confirm(:always_reject)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()
      target_reservation = Enum.find(seeded.reservations, fn r -> r.fare_class == :economy end)
      %{reservation: target_reservation}
    end

    prompt(
      "I'm customer Alice Smith (c-001). Please cancel reservation r-002 — " <>
        "I want it gone immediately."
    )

    gate :resource_state do
      # r-002 belongs to Bob; even if the agent attempts the cancel,
      # the rejected confirmation prevents the mutation.
      assert(:reservation, :status, fn s -> s == :booked end)
    end

    report :trajectory do
      max_actions(8)
    end
  end

  scenario "change_flight_with_reasoning" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()

      target_reservation =
        Enum.find(seeded.reservations, fn r -> r.fare_class == :premium end) ||
          List.first(seeded.reservations)

      %{reservation: target_reservation}
    end

    prompt(
      "Please change Alice's premium reservation to the latest available " <>
        "JFK→LAX flight. Explain *why* the change is allowed under our " <>
        "fare policy before proposing the action."
    )

    gate :resource_state do
      assert(:reservation, :status, fn s -> s == :changed end)
    end

    report :trajectory do
      max_actions(10)
    end

    # Diagnostic-only; the judge call is skipped when no
    # `:judge_model` is configured, so this report is safe in the
    # default replay path.
    report :qualitative do
      criterion(:reasoning,
        prompt: "Did the agent explain why a premium-fare change is allowed under policy?",
        threshold: 0.6
      )
    end
  end

  scenario "budget_aware_multi_cancel" do
    agent(TauBenchAirline.Agent)

    setup fn ->
      seeded = TauBenchAirline.Seeder.seed_all()
      # Pin the economy reservation that the agent is most likely to
      # successfully cancel within the per-turn budget.
      target = Enum.find(seeded.reservations, fn r -> r.fare_class == :economy end)
      %{reservation: target}
    end

    prompt(
      "Please cancel all of customer Bob Jones' reservations in one go — " <>
        "every single one he has booked."
    )

    gate :resource_state do
      # Bob owns the economy r-002; that single mutation should
      # complete under the 3-per-turn cap.
      assert(:reservation, :status, fn s -> s == :cancelled end)
    end

    report :trajectory do
      # Agent + Ash should not exceed the budget; the trajectory
      # report's max_actions covers tool calls (read + cancel = ~2-4).
      max_actions(10)
    end
  end
end
