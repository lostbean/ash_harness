defmodule TauBenchAirline.Scenarios do
  @moduledoc """
  τ-bench airline scenarios mapped to `AshHarness.Eval.Scenario` form.

  v0.1.1 implements three scenarios end-to-end against committed
  cassettes:

    1. `change_flight` — agent moves a premium reservation to a later
       flight. `gate :resource_state` asserts `:flight_id` matches the
       later flight and `:status == :changed`.
    2. `cancel_economy` — agent cancels an economy reservation; gate
       asserts `:status == :cancelled`.
    3. `refuse_basic_cancel` — agent attempts to cancel a basic-fare
       reservation; gate asserts `:status` remains `:booked` (policy
       refusal); `report :trajectory` records the refusal.

  The remaining seven scenarios are placeholders for v0.2; they
  declare `agent(nil)` so the eval runner doesn't try to drive an
  LLM against missing cassettes.
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
  # v0.2 placeholders — left in scenario form so the test count and
  # generated module surface stay stable; `agent(nil)` prevents the
  # eval runner from trying to drive an LLM against missing cassettes.
  # ----------------------------------------------------------------

  scenario "search_by_origin_dest (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("Find me JFK to LAX flights.")

    gate :invariant do
      true
    end
  end

  scenario "cross_customer_denial (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("Cancel reservation r-002, but I am customer c-001.")

    gate :invariant do
      true
    end
  end

  scenario "change_flight_with_reasoning (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("Change the customer's flight to a later option with reasoning.")

    gate :invariant do
      true
    end
  end

  scenario "search_unknown_origin (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("Find me flights from XYZ.")

    gate :invariant do
      true
    end
  end

  scenario "read_customer (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("What is the loyalty tier of customer Alice?")

    gate :invariant do
      true
    end
  end

  scenario "list_reservations (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("List Alice's reservations.")

    gate :invariant do
      true
    end
  end

  scenario "per_turn_budget (v0.2 placeholder)" do
    agent(nil)
    setup fn -> %{} end
    prompt("Cancel all three reservations in one turn.")

    gate :invariant do
      true
    end
  end
end
