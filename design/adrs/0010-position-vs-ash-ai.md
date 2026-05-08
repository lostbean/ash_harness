# ADR 0010 — Position vs `ash_ai`

## Status

Accepted (2026-05-08). Revisit after v0.1.0 ships.

## Context

The Ash ecosystem already has [`ash_ai`](https://github.com/ash-project/ash_ai),
which (per training-time research, **needs verification with current
sources**) provides:

- Prompt-backed actions (an Ash action whose `run` calls an LLM).
- A `tools` DSL on the domain that exposes Ash actions as LLM tools.
- An MCP server (`AshAi.Mcp.Router`) that mounts an Ash domain over
  MCP.
- Vectorization helpers via pgvector + `AshPostgres`.

The overlap with AshHarness is significant: both expose Ash actions to
LLMs.

## Decision

Build AshHarness as an **alternative with different opinions**, not on
top of `ash_ai`. Co-existence is fine; merging is not the v0.1.0 goal.

## Consequences

### What's different

| | `ash_ai` (per training) | AshHarness |
| --- | --- | --- |
| Agent as concept | Tool exposure layer; agent identity is implicit | First-class declarative agent module |
| Scope | Implicit (tool list per domain) | Explicit DSL block (`scope do … end`) |
| Behavior controls | Mostly via Ash policies | Scope + policies + budget + reasoning + confirmation |
| Eval | Not a built-in feature | First-class three-layer framework |
| Delegation | Not modeled | Explicit, with anti-corruption text-only return |
| Runtime | Custom + LangChain | Built on `jido_composer` |
| Progressive disclosure | Not central | First-class via Skills + DynamicAgentNode |
| MCP | Built-in router | Renderer only in v0.1.0 (router deferred) |
| Prompt-backed actions | Yes | No (different concern) |
| Vectorization helpers | Yes | No (orthogonal; users add `ash_ai`'s helpers if they want pgvector) |

### What's the same

- Both consume Ash resources.
- Both can run on top of the same domain definitions.
- Both ultimately call `Ash.create/update/destroy/read` with an actor.

### Co-existence

Nothing prevents a project from using both:

- `ash_ai`'s vectorization helpers (Ash extension).
- `ash_ai`'s prompt-backed actions where useful.
- AshHarness's agent DSL + harness for top-level agents.

We will document this in `docs/coexistence-with-ash-ai.md` after v0.1.0.

## Outcome we want

For AI/agent engineers coming from other ecosystems, AshHarness offers:

- A familiar agent-as-a-thing mental model (vs "a domain with tools").
- Strong eval support out of the box.
- A scope DSL that visibly enumerates capability — not buried in
  policy files.
- An honest, opinionated take on multi-agent (text-only delegation).

These are the differentiators. If `ash_ai` is the right answer for a
team, that's fine — we're not trying to replace it.

## Verification needed

The above comparison is from training-time knowledge (Jan 2026
cutoff). Before publishing the README, verify:

- `ash_ai`'s current feature set on GitHub.
- That our characterizations are accurate.
- Whether `ash_ai` has shipped anything closer to AshHarness's design
  in the meantime.

If `ash_ai` has converged toward AshHarness's design, we revisit
positioning.

## Alternatives considered

1. **Build on `ash_ai`.** Rejected for v0.1.0 — couples our cycle to
   theirs; adds a dependency we don't need; obscures the differences.
2. **Contribute AshHarness's distinguishing features to `ash_ai` as
   PRs.** Considered for v0.x. Possible if maintainers are receptive.
   Not the right path for *initial* design; the opinions diverge enough
   that two libraries is honest.
3. **Wait for `ash_ai` to add what we want.** Rejected — we have a
   user with a vision.
