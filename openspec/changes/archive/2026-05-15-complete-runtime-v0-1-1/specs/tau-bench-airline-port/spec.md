# tau-bench-airline-port — Specification (v0.1.1 deltas)

## MODIFIED Requirements

### Requirement: At least 3 scenarios drive the agent end-to-end

The τ-bench airline port SHALL include at least three scenarios whose
gates assert on **post-run** resource state rather than placeholder
truthy values:

1. **change_flight** — agent changes a premium reservation to a later
   flight; `gate :resource_state` asserts the reservation's
   `:flight_id` matches the later flight and `:status == :changed`.
2. **cancel_economy** — agent cancels an economy reservation;
   `gate :resource_state` asserts `:status == :cancelled`.
3. **refuse_basic_cancel** — agent receives a request to cancel a
   basic-fare reservation; `gate :resource_state` asserts
   `:status == :booked` (cancel refused by policy);
   `report :trajectory` asserts that a `:policy_denied` or
   `:validation_failed` entry appears.

Each scenario SHALL run against a committed cassette under
`benchmarks/tau_bench_airline/test/cassettes/`.

#### Scenario: change_flight scenario passes
- **WHEN** `mix tau_bench.run` executes the `change_flight` scenario
  in replay mode
- **THEN** the cassette replays without hitting the network; the
  scenario's `gate :resource_state` returns true; the result has
  `:passed == true`

#### Scenario: refuse_basic_cancel respects fare policy
- **WHEN** the `refuse_basic_cancel` scenario runs
- **THEN** the reservation's status is still `:booked` after the run;
  the trajectory shows a policy/validation refusal

### Requirement: README reports a gate-pass-rate against a real model

`benchmarks/tau_bench_airline/README.md` SHALL include a "Results"
section with at least one row recording the date, the headline model
used during cassette recording, the gate-pass-rate, and the count of
implemented vs. total scenarios. The reproduction commands SHALL
include the `mix tau_bench.run` invocation and the cassette layout.

#### Scenario: Results table is populated
- **WHEN** a reader opens the README
- **THEN** the Results table has at least one non-TBD row populated by
  a real cassette-driven run
