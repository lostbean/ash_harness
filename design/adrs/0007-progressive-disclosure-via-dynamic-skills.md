# ADR 0007 — Progressive disclosure via per-resource Skills + DynamicAgentNode

## Status

Accepted (2026-05-08).

## Context

The original spec deferred "progressive context disclosure" to a future
version. Research from training (and our v0.1.0 user decision) put it
back in scope: Anthropic's Context Editing and the broader move toward
dynamic tool-set management is now standard.

For an agent scoped over 10+ resources with multiple actions each, the
eager system prompt easily exceeds 30k tokens. We need a way to start
small and expand on demand.

`jido_composer` already provides the mechanism:
`Jido.Composer.Node.DynamicAgentNode` — the parent LLM picks which
skills to equip a sub-agent with per query.

## Decision

- Each scoped resource is a separate `Jido.Composer.Skill`.
- The orchestrator's initial node set includes a `DynamicAgentNode`
  whose `skill_registry` is the agent's full skill set.
- The initial system prompt contains:
  - Identity, vocabulary, traversal map (compact).
  - **Resource summaries** (1-2 lines per resource).
  - Strategies, delegation hints, constraints.
  - A meta-tools doc: `load_resource_skill(name)` and
    `inspect_resource(name)`.
- Full per-resource detail (attributes, actions with hints, schema)
  loads on demand via `load_resource_skill(:resource_name)`.

## Consequences

### Pros

- Initial token cost is ~3-5k for a typical 10-resource agent.
- Detail loads only when the agent actually needs it.
- Native to Jido — we don't reinvent.
- Encourages agent authors to write good per-resource summaries (the
  always-visible part).

### Cons

- The agent has to reason about what to load. Wasted turn if it loads
  the wrong thing.
- Eval scenarios must account for the load-then-act pattern (the
  trajectory will include `load_resource_skill` calls).

### Mitigations

- Resource summaries include a one-line hint about *when* to load that
  resource's full detail.
- Reachability map shows traversable connections so loading one
  resource's detail can hint at related ones.
- The eval framework's `report :trajectory` `excludes` and
  `includes_sequence` checks are aware that these meta-calls count.

## Implementation notes

- Skills are evaluated at session-start time (not compile time) so the
  skill's `prompt_fragment` reflects the current cached
  `render_resource/3` output. This lets us update detail wording
  without recompile.
- The `loaded_skills` MapSet on the session struct tracks which
  resources have been loaded.

## Alternatives considered

1. **Default-load top resources, render-on-demand for traversed.**
   Considered. Reasonable. Less powerful than DynamicAgentNode (which
   is general-purpose). Picked DynamicAgentNode because it's already
   built and natively exposed.
2. **Two-tier static (`core_resources` vs `extended`).** Rejected —
   adds DSL surface; doesn't materially improve over progressive.
3. **No progressive disclosure for v0.1.0.** Rejected — token budgets
   are real, and Jido already gives us the mechanism for free.
