# ADR 0002 — Eval scoring: gate, not weighted average

## Status

Accepted (2026-05-08).

## Context

Original spec proposed:

> Composite score: deterministic 0.5, trajectory 0.3, qualitative 0.2

Research (training-time, Jan 2026 cutoff) suggests this **departs from
current consensus** among practitioners (Braintrust, Inspect AI,
Anthropic internal eval guidance). The dominant pattern: deterministic
checks gate pass/fail; trajectory and qualitative are reported as
diagnostics.

The failure mode of weighted averaging: a high judge score papers over
a deterministic failure. For an agent that takes real actions, a
"lookpassed" with a wrong final state is exactly the failure you cannot
tolerate.

## Decision

- `gate` blocks must pass for the scenario to pass. They are binary.
- `report` blocks are observed and surfaced in the run output, but they
  do not affect pass/fail.

DSL change:

| Old | New |
| --- | --- |
| `assert_resource Foo do … end` | `gate :resource_state do … end` |
| `assert_trajectory do … end` | `report :trajectory do … end` |
| `qualitative do … end` | `report :qualitative do … end` |

`%EvalResult{}` no longer contains `composite_score`. It contains
`passed: boolean` (true iff all gates passed), `gate_results`, and
`report_results`.

## Consequences

### Pros

- Failure modes are clear and unforgivable when they should be.
- Matches mainstream eval frameworks; fewer surprises for users
  porting from Promptfoo/Inspect.
- Diagnostics still let teams track regression in trajectory shape and
  qualitative scores over time.

### Cons

- No single number to chart. Teams that want a dashboard line need to
  pick something — gate pass rate, average qualitative score by
  criterion, etc. We document patterns.

### What's still possible

A team that *wants* a single number can compute one from the diagnostic
reports — it just isn't built into AshHarness.

## Migration

The original spec was a draft. No migration concerns; this is the
v0.1.0 design.

## Alternatives considered

1. **Keep weighted average.** Rejected — see above.
2. **Hybrid: gate + composite for trending.** Rejected — gate failures
   already shadow the composite; the composite adds noise.
3. **User-configurable weights, default gating.** Rejected for v0.1.0 —
   simpler is better. If users want custom composites, they can compute
   them externally from `%Result{}`.
