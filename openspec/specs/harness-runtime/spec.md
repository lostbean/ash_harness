# harness-runtime Specification

## Purpose
TBD - created by archiving change audit-followup-v0-1-2. Update Purpose after archive.
## Requirements
### Requirement: Per-dispatch request_id

Every call to `AshHarness.Harness.GeneratedAction.dispatch/5` SHALL
generate a fresh UUID v4 binary `request_id` at entry. The id SHALL
be set as the `ash_harness.request.id` attribute on the active OTel
span and SHALL appear in the `:request_id` metadata field of every
telemetry event emitted during that dispatch. The id SHALL be
distinct from the session id and from the per-turn id.

#### Scenario: Each dispatch gets a fresh id
- **WHEN** the same session executes two consecutive tool calls
- **THEN** the two emitted `[:ash_harness, :action, :executed]` events
  carry different `:request_id` values

#### Scenario: Request id propagates to all events in the dispatch
- **WHEN** a single dispatch emits `[:ash_harness, :scope, :violation]`
- **THEN** that event's metadata contains the same `:request_id` that
  the dispatch's `ash_harness.request.id` OTel attribute carries

### Requirement: Errors module tree

The library SHALL provide structured error types under
`AshHarness.Errors`:

- `%AshHarness.Errors.ScopeViolation{agent, resource, action}`
- `%AshHarness.Errors.PolicyDenied{agent, resource, action, actor, ash_error}`
- `%AshHarness.Errors.ValidationFailed{agent, resource, action, ash_error}`
- `%AshHarness.Errors.MutationLimitExceeded{agent, count, max}`
- `%AshHarness.Errors.ReasoningRequired{agent, resource, action}`
- `%AshHarness.Errors.DelegationNotPermitted{from, to, reason}`

Each error SHALL define `defexception` with the listed fields, a
`message/1` callback producing a one-line summary, and a `Splode`
class atom suitable for OTel `error.class` attribute usage.

#### Scenario: Splode classification
- **WHEN** an error struct is inspected via
  `AshHarness.Errors.classify/1`
- **THEN** the function returns an atom in the set
  `[:scope, :policy, :validation, :budget, :reasoning, :delegation]`

### Requirement: Scope gate

The harness SHALL refuse any tool dispatch where the (resource,
action) pair is not in the agent's scope. The refusal SHALL emit
`[:ash_harness, :scope, :violation]` telemetry and return
`{:error, %AshHarness.Errors.ScopeViolation{}}` without invoking
Ash. On a successful pass the gate SHALL emit
`[:ash_harness, :scope, :checked]` with `passed: true` metadata.

#### Scenario: Out-of-scope action rejected with struct error
- **WHEN** an LLM emits a tool call for an action not in the agent's
  scope
- **THEN** the dispatch returns
  `{:error, %AshHarness.Errors.ScopeViolation{agent: A, resource: R,
  action: a}}` and Ash is not called

#### Scenario: Passing scope check emits :checked event
- **WHEN** a dispatch's (resource, action) is in scope
- **THEN** `[:ash_harness, :scope, :checked]` fires once with
  `passed: true` and the dispatch continues to the next gate

### Requirement: Reasoning gate

The harness SHALL refuse any mutating tool dispatch for an action in
`require_reasoning_for` when the input does not contain a non-empty
`reasoning` string. The refusal SHALL return
`{:error, %AshHarness.Errors.ReasoningRequired{}}` and emit
`[:ash_harness, :reasoning, :missing]`. On a successful pass the gate
SHALL emit `[:ash_harness, :reasoning, :checked]` with `required` and
`present` boolean measurements.

#### Scenario: Reasoning required but missing
- **WHEN** the agent declares `require_reasoning_for [:assign]` and
  an `:assign` call arrives without `reasoning`
- **THEN** the dispatch returns
  `{:error, %AshHarness.Errors.ReasoningRequired{}}` and Ash is not
  called

#### Scenario: Reasoning checked event fires on every gate evaluation
- **WHEN** any gated dispatch is evaluated by the reasoning gate
- **THEN** `[:ash_harness, :reasoning, :checked]` fires with
  `required` and `present` booleans regardless of pass/fail

### Requirement: Budget gate

The harness SHALL refuse any mutating action when the session's
`mutation_count` already equals the agent's `max_mutations_per_turn`.
Reads SHALL NOT contribute to the count. Failed actions SHALL NOT
contribute. The count SHALL increment only after successful
execution. The refusal SHALL return
`{:error, %AshHarness.Errors.MutationLimitExceeded{}}`. The gate
SHALL emit `[:ash_harness, :budget, :checked]` with `count` and `max`
measurements on every evaluation regardless of pass/fail.

#### Scenario: Budget exhausted returns struct error
- **WHEN** `session.mutation_count == max_mutations_per_turn` and a
  mutating tool dispatches
- **THEN** the gate returns
  `{:error, %AshHarness.Errors.MutationLimitExceeded{count: N, max: N}}`
  and Ash is not called

#### Scenario: Budget checked event fires on every gate evaluation
- **WHEN** any mutating dispatch is evaluated by the budget gate
- **THEN** `[:ash_harness, :budget, :checked]` fires with the current
  `count` and `max` measurements

### Requirement: Policy gate

The harness SHALL call `Ash.can?(actor, action_input)` before
executing any mutating action. When `Ash.can?` returns `false`, the
gate SHALL refuse execution and return
`{:error, %AshHarness.Errors.PolicyDenied{}}`. When `Ash.can?`
returns `true` or `:maybe`, execution proceeds. The gate SHALL emit
`[:ash_harness, :policy, :checked]` with `passed: boolean` on every
evaluation.

#### Scenario: Policy denies with struct error
- **WHEN** `Ash.can?` returns `false` for a tool dispatch
- **THEN** the gate emits `[:ash_harness, :policy, :denied]`, emits
  `[:ash_harness, :policy, :checked]` with `passed: false`, and the
  dispatch returns
  `{:error, %AshHarness.Errors.PolicyDenied{ash_error: _}}`

### Requirement: Trajectory entries are appended during dispatch

The harness SHALL append a `%AshHarness.Harness.TrajectoryEntry{}` to
the session's trajectory for every gate refusal and every executed
action. Entries SHALL include `:timestamp`, `:turn_number`, `:intent`,
`:result_status`, `:duration_ms`, and `:data` (a map carrying
event-specific payload; for delegation entries it SHALL include
`:reply_text` and `:target_trajectory_id`). After `run/3` returns,
the session's trajectory SHALL reflect the full per-tool-call
sequence.

#### Scenario: Delegation entry carries reply payload
- **WHEN** an LLM calls the `delegate` skill and the delegate replies
  "ok"
- **THEN** the caller's trajectory contains an entry with
  `result_status == :delegation_completed` and
  `data == %{reply_text: "ok", target_trajectory_id: tid}` where
  `tid` is a non-empty binary

#### Scenario: Non-delegation entries leave data empty
- **WHEN** a `:read` action returns successfully
- **THEN** the trajectory entry's `data` is `%{}` (or an event-
  specific empty default)

