# repair-loop — Specification (v0.1.1 deltas)

## MODIFIED Requirements

### Requirement: Per-action repair-attempt cap

The harness SHALL track the number of retryable failed attempts per
`(resource, action)` within a session via the SessionAgent's
`:repair_attempts` map. When the agent's `max_repair_loop_retries` is
reached for a given `(resource, action)`, the next dispatch SHALL
return an error tool result describing the limit reached and
suggesting a different approach, AND emit
`[:ash_harness, :repair, :exhausted]` with metadata `{agent, resource,
action, attempts}`. The counter SHALL only increment on failure
classifications considered retryable (validation errors, transport
errors). Non-retryable failures (policy denial, scope, budget)
SHALL NOT consume an attempt.

#### Scenario: Retryable failures consume attempts
- **WHEN** a `:create` action fails validation 3 times in one turn and
  `max_repair_loop_retries` is 3
- **THEN** the third attempt returns the validation feedback; the
  fourth attempt returns retry-limit feedback and emits
  `[:ash_harness, :repair, :exhausted]`

#### Scenario: Non-retryable failures don't consume attempts
- **WHEN** a `:create` action is refused by `PolicyGate` 3 times
- **THEN** the counter for `(resource, :create)` is still 0; no
  `:repair, :exhausted` event has fired
