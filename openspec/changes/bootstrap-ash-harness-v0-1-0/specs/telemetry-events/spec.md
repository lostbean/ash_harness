# telemetry-events — Specification

## ADDED Requirements

### Requirement: AshHarness telemetry namespace

All AshHarness-emitted telemetry events SHALL use the
`[:ash_harness, …]` prefix. Events SHALL be emitted via
`:telemetry.execute/3` and SHALL be documented in the
`AshHarness.Telemetry` module.

#### Scenario: Event prefix
- **WHEN** any telemetry event is emitted by AshHarness
- **THEN** the event name is a list whose first element is
  `:ash_harness`

### Requirement: Gate-pipeline events

The harness SHALL emit `[:ash_harness, :scope, :violation]`,
`[:ash_harness, :reasoning, :missing]`, `[:ash_harness,
:confirmation, :requested]`, `[:ash_harness, :confirmation,
:approved]`, `[:ash_harness, :confirmation, :rejected]`,
`[:ash_harness, :budget, :exceeded]`, and `[:ash_harness, :policy,
:denied]`, each with `agent`, `resource`, `action`, and `request_id`
metadata.

#### Scenario: Scope violation event
- **WHEN** a tool dispatch is refused by the scope gate
- **THEN** `[:ash_harness, :scope, :violation]` is emitted exactly
  once with the agent module, resource module, action atom, and
  request_id in metadata

### Requirement: Action execution event

The harness SHALL emit `[:ash_harness, :action, :executed]` for every
action execution attempt, with measurements including `duration_ms`
and metadata including agent, resource, action, status (`:ok |
:error`), and `request_id`.

#### Scenario: Successful read execution
- **WHEN** a read action succeeds
- **THEN** the event fires once with `status == :ok` and
  `duration_ms` populated

#### Scenario: Failed update execution
- **WHEN** an update action fails validation
- **THEN** the event fires once with `status == :error` and metadata
  including the error class

### Requirement: Repair loop events

The harness SHALL emit `[:ash_harness, :repair, :feedback]` each time
a repair feedback string is generated, and `[:ash_harness, :repair,
:exhausted]` when the per-action retry cap is reached.

#### Scenario: Repair attempt fires feedback event
- **WHEN** an Ash validation error is formatted for re-injection
- **THEN** `[:ash_harness, :repair, :feedback]` fires with `attempt`
  measurement and `reason_class` metadata

### Requirement: Delegation events

The harness SHALL emit `[:ash_harness, :delegation, :started]` when a
delegation begins, `[:ash_harness, :delegation, :ended]` when it
completes, and `[:ash_harness, :delegation, :denied]` when it is
refused (not permitted or depth exceeded).

#### Scenario: Successful delegation
- **WHEN** A delegates to B and B replies successfully
- **THEN** `:started` fires once with `from_agent`, `to_agent`,
  `depth`; `:ended` fires once with `duration_ms` and `status: :ok`

### Requirement: Context-rendered event

The renderer SHALL emit `[:ash_harness, :context, :rendered]` with
measurements `render_time_ms`, `token_estimate`, and `sections_count`,
and metadata `agent` and `actor_id`.

#### Scenario: Render emits event
- **WHEN** `AshHarness.ContextRenderer.render/2` is called and a
  cache miss occurs
- **THEN** the event fires exactly once with the listed measurements
  populated

### Requirement: Eval events

The eval runner SHALL emit `[:ash_harness, :eval, :scenario, :start]`
and `[:ash_harness, :eval, :scenario, :stop]`, plus
`[:ash_harness, :eval, :gate, :checked]` per gate and
`[:ash_harness, :eval, :report, :computed]` per report.

#### Scenario: Scenario emits start and stop
- **WHEN** a scenario runs to completion
- **THEN** `:start` fires before any gate checks; `:stop` fires once
  with `duration_ms`, `tokens_used`, and `passed` metadata

### Requirement: OpenTelemetry attribute attachment

When emitting AshHarness events during a Jido orchestrator tool call,
the harness SHALL attach attributes to the active OTel span using the
namespace `ash_harness.*`. Attributes SHALL include
`ash_harness.agent`, `ash_harness.resource`, `ash_harness.action`,
`ash_harness.scope.passed`, `ash_harness.policy.passed`,
`ash_harness.budget.count`, `ash_harness.budget.max`,
`ash_harness.repair.attempt`, `ash_harness.session.id`, and
`ash_harness.request.id`.

#### Scenario: Attributes added to active span
- **WHEN** a tool dispatch executes inside a Jido orchestrator tool
  span
- **THEN** the active span has `ash_harness.agent`,
  `ash_harness.resource`, and `ash_harness.action` attributes
  populated

#### Scenario: No active span
- **WHEN** an event is emitted outside any active OTel span
- **THEN** the attribute attachment is a no-op (no error, no
  telemetry-skipping)

### Requirement: Telemetry can be disabled

The library SHALL support `config :ash_harness, :telemetry, enabled:
false` to skip all `:telemetry.execute/3` calls. The default SHALL
be enabled.

#### Scenario: Disabled telemetry
- **WHEN** the config is set to `enabled: false` and any harness
  operation runs
- **THEN** no `[:ash_harness, …]` events fire (verified via attached
  test handlers)
