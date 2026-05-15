# repair-loop — Specification (v0.1.2 deltas)

## MODIFIED Requirements

### Requirement: Validation error formatting

`AshHarness.Harness.Repair.format_feedback/2` SHALL accept any term
in the `{:error, _}` shape returned by gates or the action executor,
plus an optional `%AshHarness.Harness.Intent{}`, and produce a
human-readable feedback string suitable for re-injection as an LLM
tool result. Validation feedback SHALL produce one bullet per field
error, an explanatory header, and a reminder of the action's input
schema. The formatter SHALL pattern-match on
`%AshHarness.Errors.ValidationFailed{}` structs (not the legacy atom
form) when classifying validation failures.

#### Scenario: Validation struct produces field bullets
- **WHEN** `format_feedback/2` receives
  `{:error, %AshHarness.Errors.ValidationFailed{ash_error: e}}` where
  `e` has two field errors `assigned_to` and `priority`
- **THEN** the returned string contains a bullet for each field error
  and a one-line schema reminder

### Requirement: Policy denial formatting

Policy denial feedback SHALL pattern-match on
`%AshHarness.Errors.PolicyDenied{}` and produce a non-retryable
message indicating that the agent's actor cannot perform the action
and recommending delegation if `delegates_to` is non-empty.

#### Scenario: Policy denied struct
- **WHEN** `format_feedback/2` receives
  `{:error, %AshHarness.Errors.PolicyDenied{}}` and the calling agent
  declares `delegates_to`
- **THEN** the returned string includes a suggestion to call the
  `delegate(...)` tool

### Requirement: Retryability classification

`AshHarness.Harness.Repair.retryable?/1` SHALL accept any error term
and return `true` for `%AshHarness.Errors.ValidationFailed{}` and
`%AshHarness.Errors.ReasoningRequired{}`, and `false` for
`%AshHarness.Errors.PolicyDenied{}`,
`%AshHarness.Errors.ScopeViolation{}`,
`%AshHarness.Errors.MutationLimitExceeded{}`, and
`%AshHarness.Errors.DelegationNotPermitted{}`.

#### Scenario: Struct-based classification
- **WHEN** `retryable?/1` receives each of the six error struct types
- **THEN** validation and reasoning-required return `true`; the
  other four return `false`
