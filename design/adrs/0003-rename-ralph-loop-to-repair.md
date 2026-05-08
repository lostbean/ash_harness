# ADR 0003 — Rename Ralph Loop → Repair Loop

## Status

Accepted (2026-05-08).

## Context

Original spec uses "Ralph Loop" for the validation-failure retry
pattern. The name is jargon — it references a community in-joke that
many users (especially those coming from non-Elixir agent frameworks)
won't recognize. Our v0.1.0 audience is "AI/agent engineers from other
ecosystems"; we want names they can understand on first read.

In the agent literature this pattern overlaps with **self-repair** /
**self-debug** (Chen et al., 2023; cf. Reflexion which adds episodic
memory). "Repair" is the standard noun.

## Decision

Rename "Ralph Loop" → **Repair Loop** throughout the codebase, design
docs, public API, telemetry events, and configuration keys.

| Old name | New name |
| --- | --- |
| `Ralph Loop` (concept) | Repair Loop |
| `AshHarness.Harness.RalphLoop` (module) | `AshHarness.Harness.Repair` |
| `format_error_feedback/1` | `format_feedback/1` |
| `max_ralph_loop_retries` (constraint) | `max_repair_loop_retries` |
| `[:ash_agent, :ralph_loop, :retry]` (telemetry) | `[:ash_harness, :repair, :feedback]` |

## Consequences

- New users immediately understand what the layer does from the name.
- The doc page is `08-repair-loop.md`.
- No backwards compatibility concern — pre-release.

## Alternatives considered

1. **Reflexion / ReflectionLoop** — rejected; sounds like Reflexion
   (which adds memory). We're not building memory.
2. **Recover / RecoveryLoop** — rejected; "recovery" connotes failure
   recovery (process crashes), which this is not.
3. **Retry / RetryLoop** — rejected; too generic. The mechanism is
   error-feedback-driven correction, not blind retry.
