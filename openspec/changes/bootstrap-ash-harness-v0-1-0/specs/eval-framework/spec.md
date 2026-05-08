# eval-framework — Specification

## ADDED Requirements

### Requirement: Eval module entry point

A module that calls `use AshHarness.Eval` SHALL gain a `scenario/2`
macro and SHALL be discoverable by `AshHarness.Eval.Runner.run_all/2`.
Each `scenario "<name>" do … end` block SHALL declare an `agent`,
optional `setup`, a `prompt`, zero or more `gate` blocks, and zero or
more `report` blocks.

#### Scenario: Scenario macro defines a struct
- **WHEN** an eval module declares one scenario
- **THEN** `Module.scenarios/0` (or equivalent introspection) returns
  one `%AshHarness.Eval.Scenario{}` value with the right fields

### Requirement: Gate blocks are pass/fail

A scenario SHALL fail if and only if any of its gate blocks fails.
Two gate kinds SHALL be supported: `gate :resource_state do … end`
(asserts on records by name from setup) and `gate :invariant do … end`
(asserts via custom Elixir code returning truthy). When all gates
pass the scenario passes; when any gate fails the scenario fails
regardless of report outcomes.

#### Scenario: All gates pass
- **WHEN** a scenario has two gates and both succeed
- **THEN** `result.passed == true`

#### Scenario: Single gate fails
- **WHEN** a scenario has two gates and one fails
- **THEN** `result.passed == false` and `result.gate_results` lists
  which assertion failed and the actual value observed

### Requirement: Report blocks are diagnostic

Report blocks SHALL produce diagnostics that appear in the result but
SHALL NEVER affect `result.passed`. Two report kinds SHALL be
supported: `report :trajectory` (with `max_actions`, `max_tokens`,
`includes_sequence`, `excludes` checks) and `report :qualitative`
(LLM-as-judge with `criterion :name, threshold: float, prompt:
"..."`).

#### Scenario: Trajectory report below max_actions
- **WHEN** a scenario completes with 3 actions and the report has
  `max_actions 8`
- **THEN** the trajectory report is marked passing (diagnostic) but
  even if the count exceeded 8, `result.passed` would not change due
  to gate evaluations

#### Scenario: Qualitative criterion below threshold
- **WHEN** a qualitative criterion scores 2.5 against a 3.5 threshold
- **THEN** the report records the score and a "below threshold"
  observation; `result.passed` is determined solely by gates

### Requirement: No composite weighted score

The result struct SHALL NOT contain a `composite_score` field. The
`passed` field SHALL be derived solely from gate outcomes. Diagnostic
reports MAY produce per-criterion numeric scores but the framework
SHALL NOT aggregate them into a single number.

#### Scenario: Result has no composite score
- **WHEN** a scenario completes
- **THEN** the result struct has fields `:scenario_name`, `:passed`,
  `:gate_results`, `:report_results`, `:duration_ms`,
  `:tokens_used`, `:session_trajectory` and NO field named
  `:composite_score`

### Requirement: Scenario isolation

Each scenario SHALL run in an isolated data context. For ETS-backed
resources, the scenario SHALL get a fresh ETS table or a sandbox; for
AshPostgres-backed resources, the scenario SHALL run inside a
transaction that rolls back at the end. Scenarios SHALL NOT share
mutable state.

#### Scenario: Two scenarios with same setup
- **WHEN** scenarios A and B both `create!` a record with the same
  natural key
- **THEN** both succeed without conflict — the data is reset between
  scenarios

### Requirement: Auto-confirm during eval

The eval runner SHALL provide an `auto_confirm` option (default
`:always_approve`) that handles `confirm_before` requests by
automatically responding. Other modes SHALL include `:always_reject`
and a `:custom` callback `fn intent -> :approved | :rejected end`.

#### Scenario: Default auto-approve
- **WHEN** a scenario triggers a confirmation and no auto-confirm
  override is set
- **THEN** the runner approves the request and the scenario continues

#### Scenario: Custom auto-confirm callback
- **WHEN** the runner is started with `auto_confirm: {:custom,
  fn _ -> :rejected end}`
- **THEN** every confirmation receives `:rejected` and the scenario
  records the rejection

### Requirement: Judge model configuration

Qualitative reports SHALL use a judge model configured separately from
the agent's model. The default SHALL be configurable via
`config :ash_harness, :eval, judge_model: "..."`. The judge SHALL run
through `jido_composer` (no separate provider client).

#### Scenario: Judge model is different from agent model
- **WHEN** the agent uses model `"anthropic:claude-sonnet-4-5"` and
  the eval config sets `judge_model:
  "anthropic:claude-opus-4-7"`
- **THEN** the qualitative report calls go through the judge model,
  observable as a different `model` attribute on the relevant Jido
  span

### Requirement: Runner API

`AshHarness.Eval.Runner.run/2` SHALL run a single scenario and return
an `%AshHarness.Eval.Result{}`. `AshHarness.Eval.Runner.run_all/2`
SHALL run all scenarios in an eval module and return a list.

#### Scenario: run_all returns result per scenario
- **WHEN** an eval module declares three scenarios and `run_all/2` is
  called
- **THEN** the returned list has length 3 and each element is an
  `%AshHarness.Eval.Result{}`
