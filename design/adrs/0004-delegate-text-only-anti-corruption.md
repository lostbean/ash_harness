# ADR 0004 — Delegation returns text only

## Status

Accepted for v0.1.0 (2026-05-08). May relax to two-tier in v0.2.

## Context

When agent A delegates to agent B, what does A receive back?

Mainstream agent frameworks (Swarm, A2A, OpenAI Agents handoffs) share
full conversation history or structured returns. This is convenient
but exposes a real attack surface: prompt-injection laundering across
agents. If B reads a record containing untrusted text and returns the
record verbatim, A's reasoning incorporates that untrusted text as if
it were trusted.

The DDD anti-corruption layer pattern applies here directly. The
delegate's reply must be **natural language** that A re-reads and
re-validates, not a structured object A can act on directly.

## Decision

For v0.1.0:

- The delegate returns a single text reply (string).
- A never sees B's records.
- A and B do not share conversation history.
- A and B use different actors (each agent's own
  `identity.actor`).
- A's trajectory records the delegation as one entry; B's full
  trajectory is available separately for observability/eval, not as
  context for A.

## Consequences

### Pros

- Closes prompt-injection laundering.
- Forces A to re-reason, which catches more failures than direct
  consumption of structured data.
- Each agent's authorization is independently verifiable.

### Cons

- Less efficient than structured returns when both agents are in the
  same trust zone (A and B operated by the same team, no untrusted
  inputs).
- The parent has to parse natural language even when a typed answer
  would suffice. May lead to occasional misinterpretation.

### Future relaxation

In v0.2, consider a two-tier mode:

- Cross-zone delegation: text only (current behavior).
- In-zone delegation: typed structured returns allowed.

This needs a clear definition of "trust zone" — likely a per-domain
declaration, or a per-delegate `mode: :strict | :trusted` option on
`delegate AgentB, for: "...", mode: :trusted`. We defer the design
until we have evals showing the strict-mode cost.

## Alternatives considered

1. **Always allow structured returns.** Rejected — exposes injection.
2. **Auto-decide based on whether B has policies stricter than A.**
   Rejected — too clever; users should know what they're getting.
3. **Per-delegation explicit choice.** Considered for v0.2.
