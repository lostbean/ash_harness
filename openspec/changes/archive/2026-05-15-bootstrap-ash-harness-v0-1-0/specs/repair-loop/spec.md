# repair-loop — Specification

## ADDED Requirements

### Requirement: Validation error formatting

`AshHarness.Harness.Repair.format_feedback/1` SHALL convert an Ash
validation error (`%Ash.Error.Invalid{}`) into a human-readable string
containing one bullet per error in the form `field: human-message`,
plus a final reminder of the action's accepted parameters with names,
types, and required indicators.

#### Scenario: Validation error with two field errors
- **WHEN** an Ash error contains errors on `:assigned_to` and
  `:status`
- **THEN** the formatted string contains two bullets, one per field,
  followed by an "Accepted parameters" line

#### Scenario: Validation error with no field
- **WHEN** an Ash error contains a top-level error without a field
- **THEN** the bullet uses `general:` as the prefix

### Requirement: Policy denial formatting

`AshHarness.Harness.Repair.format_feedback/1` SHALL convert an
`%Ash.Error.Forbidden{}` into a human-readable string explaining the
denial, the actor's identity, and a note that retrying with the same
actor will not succeed (the agent should consider delegation or escalation).

#### Scenario: Policy denial mentions delegation
- **WHEN** a policy-denial error is formatted and the agent has any
  `delegates_to` entries
- **THEN** the formatted string suggests delegation as a possible path

#### Scenario: Policy denial without delegates
- **WHEN** the agent has no delegates and a policy denial is formatted
- **THEN** the formatted string explains the denial without suggesting
  delegation

### Requirement: Retryability classification

`AshHarness.Harness.Repair.retryable?/1` SHALL return `true` for
validation errors and transport errors (e.g., timeouts) and `false`
for policy denials, configuration errors, and unexpected exceptions.

#### Scenario: Validation error is retryable
- **WHEN** `retryable?(%Ash.Error.Invalid{})` is called
- **THEN** the result is `true`

#### Scenario: Policy denial is not retryable
- **WHEN** `retryable?(%Ash.Error.Forbidden{})` is called
- **THEN** the result is `false`

### Requirement: Per-action repair-attempt cap

The harness SHALL track the number of repair attempts per (resource,
action) within a session and SHALL refuse further attempts on the same
action once the agent's `max_repair_loop_retries` is reached. The
refusal SHALL surface as a tool-result string explaining that the
limit is hit and suggesting a different approach.

#### Scenario: Repair limit reached
- **WHEN** an action has already had `max_repair_loop_retries` failed
  attempts and another invocation arrives
- **THEN** the dispatch returns an error with text indicating the
  retry limit is reached and `[:ash_harness, :repair, :exhausted]`
  fires

### Requirement: Output sanitization

The formatter SHALL NOT include stack traces, validator/changes
module names, internal Ash error class names, or database error codes
in its output. Configuration errors SHALL NOT be repair-formatted —
they SHALL surface to the host application as raw errors.

#### Scenario: Stack trace not exposed
- **WHEN** an Ash error carries a stacktrace
- **THEN** the formatted string contains no file paths, no
  `Elixir.Module.function/N` references, and no line numbers
