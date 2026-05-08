# ADR 0009 — Mutation budget per turn

## Status

Accepted (2026-05-08).

## Context

The original spec defines `max_mutations_per_turn` — a per-turn cap on
create/update/destroy actions. This is **AshHarness-specific**;
research did not find a named pattern in major frameworks (LangGraph
has `recursion_limit`, OpenAI Agents has `max_turns`, Claude Agent SDK
has per-tool permission gates — none are per-turn write caps).

The motivation: in agent loops gone wrong, the model can issue
many mutating tool calls before hitting any other limit. A per-turn
write cap is defense-in-depth — it catches infinite loops, cascading
edits, or "delete every record" failure modes early.

## Decision

Keep `max_mutations_per_turn` as a constraint. Default 10.

Semantics:

- Counts successful create/update/destroy and successful mutating
  generic actions (`Ash.run_action` with side effects).
- Reads do not count.
- Failed actions (validation/policy) do not count.
- The "turn" is the duration of one `AshHarness.Harness.run/2` or
  `resume/2` call. Across `run` calls (i.e., multiple user messages),
  the count resets (each is a "turn").

## Consequences

### Pros

- Catches runaway-mutation bugs early.
- Document-able — agent author sees the limit in the constraints
  block.
- Surfaced in the rendered context so the agent knows the cap.

### Cons

- Novel name; users have to learn what "turn" means here. Documented
  in the agent DSL doc.
- Per-turn vs per-session is a fine line — we may add
  `max_mutations_total` in v0.2 for stricter caps.

## Open questions

- What about generic actions whose side effects are unclear at static
  introspection? v0.1.0: count them as mutations unless the action
  declares `agent_mutates? false` (a future hint). Currently
  conservative — fewer false negatives at the cost of some false
  positives.
- Should reads count? No, by design. Read-heavy reasoning loops are
  not the failure mode we're protecting against.

## Alternatives considered

1. **Drop the budget.** Rejected — useful safety net.
2. **Session-level cap only.** Rejected — coarser, less protective.
3. **Per-resource cap.** Considered for v0.2.
