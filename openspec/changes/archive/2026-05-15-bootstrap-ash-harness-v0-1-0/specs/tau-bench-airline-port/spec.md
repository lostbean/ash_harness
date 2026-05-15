# tau-bench-airline-port — Specification

## ADDED Requirements

### Requirement: Child package layout

A separate package `ash_harness_tau_bench` SHALL host the τ-bench
airline port, with its own `mix.exs` depending on `ash_harness` and
`ash`. The package SHALL live under `benchmarks/tau_bench_airline/` in
this repository for v0.1.0.

#### Scenario: Package structure
- **WHEN** the repository builds
- **THEN** `benchmarks/tau_bench_airline/mix.exs` exists with
  application name `:ash_harness_tau_bench` and a dependency on
  `:ash_harness` from the parent path

### Requirement: Airline domain resources

The port SHALL provide three Ash resources backing the airline
benchmark: `TauBenchAirline.Customer` (id, name, email, loyalty_tier
in `[:basic, :silver, :gold, :platinum]`), `TauBenchAirline.Reservation`
(id, customer_id, flight_id, fare_class, status, purchase_date,
ticket_price, with policies enforcing per-customer ownership), and
`TauBenchAirline.Flight` (id, origin, destination, departure_at,
seats_available, base_price). Resources SHALL use
`Ash.DataLayer.Ets` for v0.1.0 by default and SHALL annotate
themselves with `AshHarness.Resource`.

#### Scenario: Reservation policy enforces customer
- **WHEN** an actor whose `customer_id` differs from a reservation's
  `customer_id` attempts `:change_flight` or `:cancel`
- **THEN** the action is denied by Ash policy

### Requirement: Airline agent module

`TauBenchAirline.Agent` SHALL declare an AshHarness agent scoped over
the three resources with appropriate `auto_execute` (reads),
`confirm_before` (`:change_flight`, `:cancel`), and
`require_reasoning_for` (`:change_flight`, `:cancel`) blocks, plus
constraints aligned with τ-bench expectations
(`max_mutations_per_turn 3`, `max_repair_loop_retries 2`).

#### Scenario: Agent compile
- **WHEN** the package compiles
- **THEN** `TauBenchAirline.Agent` is a valid AshHarness agent
  module — compile succeeds and `AshHarness.Agent.Info.tool_list/1`
  returns at least the read, change_flight, cancel, and search tools

### Requirement: User simulator agent

The port SHALL provide a `TauBenchAirline.UserSimulator` AshHarness
agent with empty scope (no Ash actions) that converses on behalf of
a simulated customer with a goal. The simulator's `identity.actor`
SHALL be the simulated user.

#### Scenario: Simulator has no scope
- **WHEN** `AshHarness.Agent.Info.scoped_resources(UserSimulator)` is
  called
- **THEN** the result is the empty list — the simulator only
  converses, it does not act on resources

### Requirement: Scenario suite

The port SHALL provide at least 10 scenarios that translate τ-bench
airline tasks into `AshHarness.Eval` form, each with a `setup`
seeding initial data from JSON fixtures, a `prompt` (or a
multi-turn user-simulator integration), `gate :resource_state`
asserting end-state, and `report :trajectory` and
`report :qualitative` diagnostics.

#### Scenario: Suite runs
- **WHEN** `mix tau_bench.run` is invoked
- **THEN** at least 10 scenarios execute and the runner reports
  per-scenario gate pass/fail and aggregate gate-pass-rate

### Requirement: JSON fixture seeding

The port SHALL include `data/customers.json`, `data/reservations.json`,
`data/flights.json`, and `data/tasks.json` and SHALL seed Ash
resources from these fixtures during scenario `setup`. The fixtures
SHALL be sourced from current public τ-bench airline data and
documented for verification.

#### Scenario: Fixture-backed setup
- **WHEN** a scenario's setup runs
- **THEN** the corresponding records exist in the data layer with
  fields populated from the JSON fixtures

### Requirement: Multi-turn runner

The port SHALL provide a custom eval-runner extension that orchestrates
multi-turn conversation between the airline agent and the user
simulator until the user's goal is met or a per-scenario `max_turns`
is reached.

#### Scenario: Loop terminates on goal
- **WHEN** the user simulator declares its goal as met (via a
  structured signal in its reply)
- **THEN** the multi-turn runner stops and runs gates against the
  final resource state

#### Scenario: Loop terminates on max_turns
- **WHEN** `max_turns` (default 12) is reached without goal
  completion
- **THEN** the runner stops, runs gates, and the result records
  `terminated_reason: :max_turns`

### Requirement: Public results report

The port SHALL produce a markdown report (`benchmarks/tau_bench_airline/
README.md`) showing gate-pass-rate over the implemented task subset,
the model used, the date, and reproduction commands.

#### Scenario: Reproducible run
- **WHEN** a reader follows the report's commands
- **THEN** they can replay the same scenarios on the same model and
  receive comparable results
