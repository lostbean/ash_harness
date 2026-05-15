# telemetry-events Specification

## Purpose
TBD - created by archiving change audit-followup-v0-1-2. Update Purpose after archive.
## Requirements
### Requirement: Gate pass-events

For every gate evaluation (regardless of outcome), the harness SHALL
emit a `:checked` event:

- `[:ash_harness, :scope, :checked]` with metadata
  `%{agent, resource, action, passed, request_id}`
- `[:ash_harness, :reasoning, :checked]` with measurements
  `%{required, present}` (booleans) and metadata
  `%{agent, resource, action, request_id}`
- `[:ash_harness, :budget, :checked]` with measurements
  `%{count, max}` and metadata
  `%{agent, resource, action, request_id}`
- `[:ash_harness, :policy, :checked]` with metadata
  `%{agent, resource, action, passed, request_id}`

These events SHALL fire whether the gate passes or refuses. Listeners
can use them to compute pass-rate metrics without OTel span sampling.

#### Scenario: Pass-events fire on success
- **WHEN** a tool dispatch passes the full gate pipeline and executes
- **THEN** all four `:checked` events have fired once each with
  `passed: true` (where applicable) and the same `:request_id`

#### Scenario: Pass-events fire on failure
- **WHEN** the policy gate refuses a dispatch
- **THEN** `[:ash_harness, :scope, :checked]`,
  `[:ash_harness, :reasoning, :checked]`,
  `[:ash_harness, :budget, :checked]`, and
  `[:ash_harness, :policy, :checked]` have all fired; the last has
  `passed: false`; `[:ash_harness, :policy, :denied]` has also fired

### Requirement: AshHarness telemetry namespace

All AshHarness-emitted telemetry events SHALL use the
`[:ash_harness, …]` prefix. Events SHALL be emitted via
`:telemetry.execute/3` and SHALL be documented in the
`AshHarness.Telemetry` module. Every event whose metadata includes
`:request_id` SHALL carry the per-dispatch UUID generated at
`GeneratedAction.dispatch/5` entry, allowing listeners to correlate
all events for a single tool call.

#### Scenario: Event prefix
- **WHEN** any telemetry event is emitted by AshHarness
- **THEN** the event name is a list whose first element is
  `:ash_harness`

#### Scenario: Request id is consistent within a dispatch
- **WHEN** a single dispatch emits any combination of scope, budget,
  policy, action, or repair events
- **THEN** every emitted event's metadata `:request_id` field is
  identical

### Requirement: Gate-pipeline events

The harness SHALL emit the following failure-class events:

- `[:ash_harness, :scope, :violation]` with metadata
  `%{agent, resource, action, request_id}`
- `[:ash_harness, :reasoning, :missing]` with metadata
  `%{agent, resource, action, request_id}`
- `[:ash_harness, :confirmation, :requested]` with metadata
  `%{agent, resource, action, request_id}`
- `[:ash_harness, :confirmation, :approved]` with measurements
  `%{duration_ms}` and metadata
  `%{agent, resource, action, respondent, request_id}`
- `[:ash_harness, :confirmation, :rejected]` with metadata
  `%{agent, resource, action, respondent, request_id}`
- `[:ash_harness, :budget, :exceeded]` with metadata
  `%{agent, resource, action, count, max, request_id}`
- `[:ash_harness, :policy, :denied]` with metadata
  `%{agent, resource, action, ash_error_class, request_id}`

`:respondent` is a binary or atom identifying who approved or
rejected (an actor identifier supplied by the host or the literal
`:auto_confirm` when auto-confirm modes apply). `:ash_error_class`
is the Splode class of the Ash error that triggered the denial.

#### Scenario: Confirmation approved metadata
- **WHEN** a `confirm_before` action is approved by a human via
  `Harness.resume/2`
- **THEN** `[:ash_harness, :confirmation, :approved]` fires once with
  `duration_ms > 0`, `respondent` set to the approver, and the same
  `request_id` as the `:requested` event

#### Scenario: Policy denied metadata
- **WHEN** `Ash.can?` returns `false` for a tool dispatch
- **THEN** `[:ash_harness, :policy, :denied]` fires with
  `ash_error_class: :forbidden` (or the relevant Splode class)

### Requirement: Action execution event

The harness SHALL emit `[:ash_harness, :action, :executed]` for every
action execution attempt, with measurements
`%{duration_ms, records_returned, records_changed}` (where
`records_returned` is non-nil for `:read` and `records_changed` is
non-nil for mutating actions; the other is `nil`) and metadata
`%{agent, resource, action, status, error_class, request_id}` where
`error_class` is `nil` on success and the Splode error class on
failure.

#### Scenario: Successful read execution
- **WHEN** a read action succeeds and returns 12 records
- **THEN** the event fires once with `status: :ok`,
  `records_returned: 12`, `records_changed: nil`, `error_class: nil`,
  and `duration_ms > 0`

#### Scenario: Failed update execution
- **WHEN** an update action fails validation
- **THEN** the event fires once with `status: :error`,
  `error_class: :validation`, and `records_changed: nil`

#### Scenario: Successful create execution
- **WHEN** a create action succeeds and writes one record
- **THEN** the event fires with `status: :ok`, `records_changed: 1`,
  and `records_returned: nil`

### Requirement: Repair loop events

The harness SHALL emit `[:ash_harness, :repair, :feedback]` each time
a repair feedback string is generated, with measurements
`%{attempt}` reflecting the **actual** current attempt count for the
target `(resource, action)` (drawn from the SessionAgent's
`:repair_attempts` map). It SHALL emit
`[:ash_harness, :repair, :exhausted]` when the per-action retry cap
is reached, with measurements `%{total_attempts}` (renamed from
`attempts`) and metadata `%{agent, resource, action, request_id}`.

#### Scenario: Repair attempt counter reflects reality
- **WHEN** the same `(:create, Ticket)` fails validation for the
  third time in a turn
- **THEN** `[:ash_harness, :repair, :feedback]` fires with
  `attempt: 3` (not the hardcoded `1`)

#### Scenario: Exhausted event renames attempts → total_attempts
- **WHEN** `max_repair_loop_retries` is reached for an action
- **THEN** `[:ash_harness, :repair, :exhausted]` fires with
  `total_attempts: N` measurement (matching the cap)

### Requirement: Delegation events

The harness SHALL emit `[:ash_harness, :delegation, :started]` when a
delegation begins, with metadata
`%{from_agent, to_agent, depth, target_trajectory_id, request_id}`.
It SHALL emit `[:ash_harness, :delegation, :ended]` when it
completes, with measurements `%{duration_ms}` and metadata
`%{from_agent, to_agent, status, depth, target_trajectory_id, request_id}`.
It SHALL emit `[:ash_harness, :delegation, :denied]` when refused.

#### Scenario: Started metadata
- **WHEN** A delegates to B at depth 2
- **THEN** `:started` fires with `from_agent: A`, `to_agent: B`,
  `depth: 2`, a non-empty `target_trajectory_id`, and a `request_id`

#### Scenario: Started/ended share trajectory id
- **WHEN** a delegation runs to completion
- **THEN** `:started` and `:ended` for that delegation carry the
  same `target_trajectory_id`

### Requirement: Eval events

The eval runner SHALL emit `[:ash_harness, :eval, :scenario, :start]`
and `[:ash_harness, :eval, :scenario, :stop]`, the latter with
metadata `%{scenario, agent, passed, gates_passed, gates_failed}`.
It SHALL emit `[:ash_harness, :eval, :gate, :checked]` per gate with
metadata `%{scenario, kind, passed}`, and
`[:ash_harness, :eval, :report, :computed]` per report with metadata
`%{scenario, kind, observations}`.

#### Scenario: Scenario stop carries gate breakdown
- **WHEN** a scenario completes with 3 passing gates and 1 failing
- **THEN** `:stop` fires with `gates_passed: 3, gates_failed: 1`,
  `agent: <agent_module>`, and `passed: false`

#### Scenario: Gate checked event carries scenario context
- **WHEN** any eval gate runs
- **THEN** the `:gate, :checked` event includes the scenario name and
  a `passed` boolean

#### Scenario: Report computed carries observations
- **WHEN** a `report :trajectory` block evaluates and observes
  `%{action_count: 5}`
- **THEN** the `:report, :computed` event includes
  `observations: %{action_count: 5}`

