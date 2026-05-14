# eval-framework — Specification (v0.1.1 deltas)

## MODIFIED Requirements

### Requirement: Runner drives the agent end-to-end

`AshHarness.Eval.Runner.run/2` SHALL, for each scenario:

1. Open a sandbox via `AshHarness.Eval.Sandbox.open/1` (ETS
   delete-all-objects for ETS-backed resources; AshPostgres
   `Sandbox.checkout/2` for postgres-backed resources, when
   applicable).
2. Invoke the scenario's `setup` (if any).
3. Build a session via `AshHarness.Harness.new_session/2`, with the
   scenario's agent and `:req_options` carrying a `:plug` configured
   for cassette replay via `ReqCassette.with_cassette/2`.
4. Loop: call `Harness.run/3` with the scenario's `prompt`; on
   `{:halt, request, session}` materialize an `%ApprovalResponse{}`
   per the runner's `:auto_confirm` mode and call
   `Harness.resume/2`; repeat until the agent returns `{:ok, reply,
   session}` or a terminal `{:error, reason, session}`, or until a
   per-runner `max_turns` is reached (default 12).
5. Build `ctx` with `:records` populated by re-reading resources from
   the data layer, `:trajectory` from `Harness.trajectory(session)`,
   and `:session` for opaque host inspection.
6. Evaluate gates and reports against `ctx`.
7. Close the sandbox (rollback transaction / leave ETS empty).

#### Scenario: Runner drives a real conversation
- **WHEN** a scenario whose setup creates a record and whose prompt
  asks the agent to update that record runs
- **THEN** at the time gates evaluate, the data layer reflects the
  agent's mutations; `ctx[:trajectory]` is non-empty

#### Scenario: max_turns aborts an infinite loop
- **WHEN** an LLM keeps emitting tool calls without completing
- **THEN** the runner stops after `max_turns` iterations; the
  resulting `%Result{}` has `:terminated_reason == :max_turns`

### Requirement: Cassette-driven replay for default `mix test`

The runner SHALL wrap agent execution in `ReqCassette.with_cassette/2`,
passing the resulting plug to the agent's request options. The cassette
name SHALL be derived from `{eval_module, scenario.name}` as
`test/cassettes/<module-snake-case>/<scenario-snake-case>.json`.
Cassette mode SHALL be controlled by the `ASH_HARNESS_CASSETTE_MODE`
environment variable: `replay` (default) fails on missing cassettes;
`record` hits the real LLM and writes new cassettes; `bypass` hits
the real LLM without writing.

#### Scenario: Default mode replays cassettes
- **WHEN** `ASH_HARNESS_CASSETTE_MODE` is unset and `mix test` runs an
  eval scenario whose cassette exists
- **THEN** no HTTP request is made to the LLM provider; the recorded
  responses drive the agent

#### Scenario: Missing cassette in replay mode fails loudly
- **WHEN** an eval scenario runs in replay mode but no cassette exists
  for it
- **THEN** the runner returns `{:error, {:missing_cassette, ...}, _}`
  or surfaces ReqCassette's missing-cassette error

### Requirement: Auto-confirm modes are honored end-to-end

The runner's `:auto_confirm` option SHALL be one of `:always_approve`
(default), `:always_reject`, or `{:custom, fn intent -> :approved |
:rejected end}`. The runner SHALL handle each `{:halt, request,
session}` from `Harness.run/3` by constructing an
`%ApprovalResponse{}` per the configured mode and resuming via
`Harness.resume/2`. Scenarios MAY override the runner-level setting
via the `auto_confirm/1` macro inside their `scenario` block.

#### Scenario: Always-reject records the rejection
- **WHEN** `Eval.Runner.run/2` is started with `auto_confirm:
  :always_reject` and the agent triggers a confirm_before tool
- **THEN** the trajectory contains a
  `:result_status == :confirmation_rejected` entry; the underlying
  mutation did not occur

#### Scenario: Per-scenario override beats runner default
- **WHEN** the runner is invoked with `auto_confirm: :always_approve`
  but the scenario block declares `auto_confirm :always_reject`
- **THEN** the scenario uses `:always_reject`

### Requirement: Scenario isolation via sandbox

Each scenario SHALL execute against fresh resource state. For ETS-
backed resources, the runner SHALL clear all tables of resources
referenced in the scenario's setup before running. For AshPostgres-
backed resources, the runner SHALL `Ecto.Adapters.SQL.Sandbox.checkout`
a connection and roll back at the end of the scenario.

#### Scenario: Two scenarios with overlapping setup
- **WHEN** scenarios A and B both create a record with the same
  natural key
- **THEN** both run without conflict; the data is reset between them
