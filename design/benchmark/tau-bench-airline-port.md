# τ-bench airline domain port

## Goal

Port the τ-bench airline domain into Ash resources as the **headline
benchmark** for AshHarness v0.1.0. This validates the library against a
known, third-party agent benchmark with public results — giving us
external credibility beyond a hand-crafted demo.

## Why airline (not retail)

User decision (interview round 3). The airline domain is "the
trip-planner-ish thing you remembered." It tests:

- Multi-step reasoning (find flight → check policy → modify booking).
- Policy adherence (fare classes, change windows, cancellation rules).
- User simulation (bench drives an LLM-as-user to interact).

Retail is a strong second; we may port it for v0.2 to demonstrate
multi-domain breadth.

## What τ-bench provides

- A **domain database** (initial state of customers, reservations,
  flights).
- A **policy document** (the airline's rules — what's allowed under
  what conditions).
- A **user simulator** (an LLM acting as a customer with a goal).
- A **task suite** (~50 airline tasks; e.g., "change the date on my
  reservation if my fare class allows").
- A **scoring rule**: did the agent achieve the user's goal while
  following policy?

## Port shape

```text
benchmarks/tau_bench_airline/
├── lib/
│   ├── tau_bench_airline/
│   │   ├── application.ex
│   │   ├── domain.ex                       # AshHarness.Domain
│   │   ├── customer.ex                     # Ash.Resource
│   │   ├── reservation.ex                  # Ash.Resource (with policies)
│   │   ├── flight.ex                       # Ash.Resource
│   │   ├── policy_document.ex              # the airline policy doc
│   │   ├── agent.ex                        # the AshHarness.Agent
│   │   └── user_simulator.ex               # drives the bench
├── data/
│   ├── customers.json                      # seed data from τ-bench
│   ├── reservations.json
│   └── tasks.json                          # the task suite
├── test/
│   └── tau_bench_test.exs                  # AshHarness.Eval scenarios
└── mix.exs
```

## Mapping τ-bench concepts → AshHarness

| τ-bench | AshHarness |
| --- | --- |
| Domain database (in-memory) | `Ash.DataLayer.Ets` resources, seeded from JSON |
| Policy document (text) | Embedded into agent's `identity.description` + a `strategy` |
| User simulator | A separate `AshHarness.Agent` configured with the user's goal |
| Task | An `AshHarness.Eval.Scenario` |
| Pass/fail | The scenario's `gate :resource_state` |
| Trajectory inspection | `report :trajectory` |

## Resources sketched

### `TauBenchAirline.Customer`

```elixir
attributes do
  uuid_primary_key :id
  attribute :name, :string
  attribute :email, :string
  attribute :loyalty_tier, :atom,
    constraints: [one_of: [:basic, :silver, :gold, :platinum]]
end

actions do
  defaults [:read]
end

agent_annotations do
  description "A customer with a loyalty tier. Loyalty tier determines change/cancel benefits."
  traversable [:reservations]
end
```

### `TauBenchAirline.Reservation`

```elixir
attributes do
  uuid_primary_key :id
  attribute :customer_id, :uuid
  attribute :flight_id, :uuid
  attribute :fare_class, :atom,
    constraints: [one_of: [:economy, :main_cabin, :business, :first]]
  attribute :status, :atom,
    constraints: [one_of: [:active, :changed, :cancelled]]
  attribute :purchase_date, :utc_datetime
  attribute :ticket_price, :decimal
end

actions do
  defaults [:read]

  update :change_flight do
    accept [:flight_id]
    # Validations encode policy: e.g., basic fare cannot change
    validate fn changeset ->
      ... policy enforcement ...
    end
  end

  update :cancel do
    change set_attribute(:status, :cancelled)
    # Refund logic per policy
  end
end

policies do
  # The actor is the agent on behalf of the customer; check ownership
  policy action_type([:update]) do
    authorize_if expr(customer_id == ^actor(:customer_id))
  end
end

agent_annotations do
  description "A flight reservation. Subject to airline change/cancel policy by fare class."
  hint :change_flight, "Use to modify the flight on an existing reservation. Subject to fare-class policy."
  hint :cancel, "Use to cancel a reservation. Subject to refund policy."
  traversable [:customer, :flight]
end
```

### `TauBenchAirline.Flight`

```elixir
attributes do
  uuid_primary_key :id
  attribute :origin, :string
  attribute :destination, :string
  attribute :departure_at, :utc_datetime
  attribute :seats_available, :integer
  attribute :base_price, :decimal
end

actions do
  defaults [:read]

  read :search do
    argument :origin, :string, allow_nil?: false
    argument :destination, :string, allow_nil?: false
    argument :date_range, :map, allow_nil?: false
    # filter implementation
  end
end

agent_annotations do
  description "An available flight from origin to destination."
  hint :search, "Use to find candidate flights matching origin, destination, and date range."
end
```

## The agent

```elixir
defmodule TauBenchAirline.Agent do
  use AshHarness.Agent, domains: [TauBenchAirline.Domain]

  identity do
    name "Airline Customer Service Agent"
    description """
    You are a customer service agent for an airline. You help customers
    with reservations, flight changes, and cancellations. You must
    strictly follow the airline policy:

    <policy embedded here>
    """
    actor TauBenchAirline.Actors.agent_for_customer/1   # function form
  end

  scope do
    resource Customer do
      actions [:read]
    end
    resource Reservation do
      actions [:read, :change_flight, :cancel]
    end
    resource Flight do
      actions [:read, :search]
    end
  end

  behavior do
    auto_execute   [:read, :search]
    confirm_before [:change_flight, :cancel]

    strategy :policy_first,
      "Always read the policy and verify allowed before suggesting an action."
    strategy :search_then_act,
      "Search for candidates first; let the customer choose; then execute."
  end

  constraints do
    max_mutations_per_turn 3
    require_reasoning_for [:change_flight, :cancel]
    max_repair_loop_retries 2
  end
end
```

The actor `TauBenchAirline.Actors.agent_for_customer/1` is a function that
takes the current scenario's customer and returns a struct with that
customer's `customer_id` set, so Ash policies enforce the per-customer
boundary.

## Eval shape

Each τ-bench task becomes a scenario:

```elixir
scenario "change date on flexible reservation" do
  agent TauBenchAirline.Agent

  setup do
    # Seed initial DB from τ-bench JSON
    customer = seed_customer("CUST-001", :gold)
    flight   = seed_flight("FL-100", "SFO", "JFK", ~U[2026-06-01 09:00:00Z])
    reservation = seed_reservation(customer, flight, :main_cabin)
    %{customer: customer, reservation: reservation}
  end

  prompt """
  (User simulator goal: change my reservation #{reservation.id} from
   FL-100 to a flight three days later. I'm a Gold member with a
   main-cabin fare.)
  """

  gate :resource_state do
    assert :reservation, :status, &(&1 == :changed)
    assert :reservation, :flight_id, &(&1 != flight.id)
  end

  report :trajectory do
    max_actions 10
    includes_sequence [
      {:read, Flight, :search},
      {:update, Reservation, :change_flight}
    ]
    excludes [
      {:destroy, Reservation, :destroy}
    ]
  end

  report :qualitative do
    criterion :policy_adherence,
      prompt: "Did the agent verify policy before changing the reservation? Score 0-5.",
      threshold: 4.0
    criterion :customer_friendliness,
      threshold: 3.5
  end
end
```

## User simulator integration

τ-bench drives interaction via an LLM acting as a customer with a
goal. We model this as a second `AshHarness.Agent` whose scope is empty
(it has no Ash actions; it only converses):

```elixir
defmodule TauBenchAirline.UserSimulator do
  use AshHarness.Agent, domains: []

  identity do
    name "Customer (simulated)"
    description "A customer with a specific goal. Asks the agent for help."
    actor %{type: :user_simulator}
  end

  # No scope — this agent only talks.
end
```

The runner orchestrates a multi-turn conversation:

```text
loop until goal_achieved or max_turns:
  user_msg = UserSimulator.respond(history, goal)
  {agent_msg, agent_session} = Agent.run(agent_session, user_msg)
  history = history ++ [user_msg, agent_msg]
```

This loop is implemented as a custom eval runner extension (test-only,
not part of the main library API).

## Scoring

τ-bench's official scoring is goal-completion + policy-adherence. We map
this to AshHarness:

- **goal_completion** → `gate :resource_state` (did the data end up in
  the right state?).
- **policy_adherence** → Ash policies enforce; `report :qualitative`
  with the `policy_adherence` criterion captures the LLM-judge view.

Public τ-bench leaderboards report a single percentage. We can compute
gate-pass-rate over the full task suite as our reportable number.

## Status / scope of effort

- **v0.1.0**: Port enough tasks (~10) to demonstrate the library works
  on a known benchmark. Run them. Report numbers.
- **v0.2.0**: Full ~50-task port; tighter user-simulator harmony.

## Verification needed

This document is sketched from training-time knowledge of τ-bench.
Before implementing, verify:

- The current public schema of τ-bench airline (resources, fields,
  policies).
- The exact task suite structure (JSON shape).
- Whether τ-bench has been updated since Jan 2026 cutoff.

The Ash port follows the *current* τ-bench definitions, not whatever
version this design references.

## Open questions

- **Should the τ-bench port be a separate hex package?** Yes — keeps
  the main library lean. Suggested name: `ash_harness_tau_bench`.
- **How do we share the user simulator across other benchmarks (e.g.,
  retail in v0.2)?** Extract `AshHarness.Eval.UserSimulator` to the
  main library if the pattern recurs.
