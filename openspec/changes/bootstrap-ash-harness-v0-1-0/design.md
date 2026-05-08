## Context

The repository ships a 35-file design folder under `design/` with 10 ADRs
that lock the architectural decisions for AshHarness v0.1.0. `lib/` and
`test/` contain only an `AshHarness.hello/0` placeholder. This change
turns the design into running code.

The design folder is canonical. Where this design.md is shorter than
`design/`, the design folder wins. Specifically, the following docs are
load-bearing for implementers:

- `design/architecture/system-context.md` — what AshHarness owns vs.
  doesn't.
- `design/architecture/jido-integration.md` — the runtime contract.
- `design/architecture/data-flow.md` — request lifecycle (compile-time
  + runtime).
- `design/architecture/module-tree.md` — file layout.
- `design/layers/01-eval.md` through `design/layers/11-telemetry.md` —
  per-layer specs.
- `design/adrs/0001` through `design/adrs/0010` — decisions with
  consequences.

User-facing constraints from the design interview:

- Audience for v0.1.0: AI/agent engineers from other ecosystems
  (LangGraph/Swarm-fluent, Elixir/Ash novices). Names and docs lean
  toward this audience.
- Headline benchmark: τ-bench airline domain ported to Ash, in a
  separate child package (`benchmarks/tau_bench_airline/`).
- Web research tools were unavailable during design. Three claims need
  verification before publishing the README: current state of
  `ash_ai`, current `jido_composer` API surface, current τ-bench
  airline shape. Tracked in `design/implementation/open-questions.md`.

## Goals / Non-Goals

**Goals:**

- A working, hex-publishable `ash_harness` library for v0.1.0 covering
  every spec in `openspec/changes/bootstrap-ash-harness-v0-1-0/specs/`.
- An end-to-end demo agent on test resources passing the full eval
  suite.
- A τ-bench airline port (≥10 scenarios) that produces a reproducible
  gate-pass-rate.
- A public-API surface stable across v0.1.x patch releases.
- CI matrix: `mix test` (default ETS), `MIX_ENV=postgres mix test`,
  `MIX_ENV=integration mix test` (nightly).

**Non-Goals:**

- Streaming partial responses through the harness.
- Multi-model routing.
- Cross-session persistent agent memory.
- An MCP server router (only the renderer ships).
- Phoenix LiveView UI components.
- Two-tier delegation (structured returns within trust zone).
- Pairwise qualitative scoring.
- Full ~50-task τ-bench airline coverage (only ≥10 in v0.1.0).
- Replacing or merging into `ash_ai`.
- Reinventing `jido_composer`'s LLM loop, HITL plumbing, or OTel
  spans.

## Decisions

### D1. Runtime is `jido_composer`, not a custom loop

`jido_composer` (v0.5.x) provides `Orchestrator`, `Skill`, `HumanNode`,
`ApprovalRequest`/`ApprovalResponse`, checkpointing, OTel
instrumentation, and dynamic skill assembly via `DynamicAgentNode`. We
build on it; we do not rebuild it.

- AshHarness has no `LLM.Adapter` behaviour. No mock provider.
- The harness's `new_session/2` assembles a Jido orchestrator using
  `Jido.Composer.Skill.assemble/2` (or the module-form orchestrator
  when needed) and tracks an `%AshHarness.Harness.Session{}` that
  carries the orchestrator state.
- The harness's `run/3` delegates the LLM loop to Jido and intercepts
  via the generated `Jido.Action.run/2` to enforce gates.
- Confirmation halts surface as Jido suspension directives.

**Alternative considered:** roll our own loop, depend on `langchain` for
transport. Rejected — duplicates work the user already shipped (ADR
0001).

### D2. Eval scoring: gate, not weighted average

`gate :resource_state` and `gate :invariant` blocks are pass/fail.
`report :trajectory` and `report :qualitative` blocks are diagnostic;
they appear in the result but do not affect `result.passed`. There is
no `composite_score`.

- Matches mainstream practice (Braintrust, Inspect AI).
- The original spec's weighted average (.5/.3/.2) was rejected: a high
  judge score papering over a deterministic failure is exactly the
  failure mode we cannot tolerate (ADR 0002).

### D3. Naming: AshHarness umbrella; Repair Loop, not Ralph Loop

- Library = `AshHarness`. Mix package = `ash_harness`. Module tree
  rooted at `AshHarness.*`. The original `AshAgent` spec is superseded.
- "Ralph Loop" is renamed to **Repair Loop** (`AshHarness.Harness.Repair`,
  constraint key `max_repair_loop_retries`, telemetry
  `[:ash_harness, :repair, :feedback]`). ADR 0003.
- Eval renames: `assert_resource` → `gate :resource_state`,
  `assert_trajectory` → `report :trajectory`, `qualitative` →
  `report :qualitative`. ADR 0002.

### D4. Tool generation: hybrid (compile-time default + runtime escape)

Per ADR 0005:

- Compile-time: per-action `Jido.Action` modules + per-resource
  `Jido.Composer.Skill`. The default for the 90% case.
- Runtime: `AshHarness.Tool.dynamic/2` for session-scoped tools
  (finalizers, conditional tools, host-app injections).
- Both flow through the same scope/reasoning/budget/policy gate
  pipeline. Dynamic tools cannot widen scope at runtime.

### D5. One canonical schema, three renderers

Per ADR 0006: derive `%AshHarness.Schema.Canonical{}` once at compile
time, render to Anthropic / OpenAI / MCP via pure functions. Adding a
new format = one new renderer module.

The MCP **renderer** ships in v0.1.0; an actual MCP **server** does
not (`hermes_mcp` exists, `ash_ai` has its own). Users who want MCP
exposure today wire the canonical schemas into a router themselves.

### D6. Progressive disclosure via per-resource Skills + DynamicAgentNode

Per ADR 0007:

- Initial system prompt: identity + vocabulary + per-resource
  *summaries* (1-2 lines) + traversal map + strategies + delegation
  hints + constraints + meta-tools doc.
- Full per-resource detail loads on demand via the
  `load_resource_skill(:resource_name)` meta-tool, backed by
  `Jido.Composer.Node.DynamicAgentNode`.
- Cuts initial token cost from ~30k to ~3-5k for a 10-resource agent.

### D7. Spark conventions: transformers persist; verifiers validate

This is a hard project rule. Transformers run early, mutate DSL state
(persist reachability graph, persist tool list). Verifiers run after
all transformers and read final state to validate. Reversing this leads
to ordering bugs.

- Use `Spark.InfoGenerator` for Info modules. Don't roll introspection
  by hand.
- Transformers must declare `after?(Ash.Resource.Transformers.SetPrimaryActions)`
  when reading action metadata.
- Use `Spark.Dsl.Transformer.persist/3` for derived state the Info
  module exposes.

### D8. Authorization is enforced inside the generated Action

`Ash.can?` and `Ash.run_action/Ash.create/Ash.update/Ash.destroy` run
inside `AshHarness.Harness.GeneratedAction.dispatch/5`, before any Ash
mutation. We do **not** delegate authorization to Jido. The agent's
declared scope plus the actor's policy permissions form a two-layer
defense.

### D9. Delegation: anti-corruption boundary, text only

Per ADR 0004:

- Delegate session is fresh; delegate uses its own
  `identity.actor`; conversation history is not shared.
- Reply is a string; structured returns are not allowed in v0.1.0.
- Depth limit (default 3) enforced.
- More cautious than mainstream multi-agent frameworks; deliberately
  so. Two-tier mode (structured within trust zone) deferred to v0.2.

### D10. Data layer: agnostic; ETS default

Per ADR 0008:

- The library operates on `Ash.Resource` and `Ash.Domain`; no data-layer
  coupling.
- Test resources use `Ash.DataLayer.Ets`.
- `ash_postgres` is `optional: true`. AshPostgres-flavored examples
  live under `examples/postgres/` and run only when
  `MIX_ENV=postgres`.
- τ-bench port defaults to ETS; can swap to Postgres.

### D11. Mutation budget per turn (AshHarness-novel)

Per ADR 0009. `max_mutations_per_turn` counts successful mutations
within one `run/2`/`resume/2` call. Reads don't count; failed mutations
don't count. Default 10. AshHarness-specific; not standard in major
frameworks.

### D12. Position vs `ash_ai`: alternative with different opinions

Per ADR 0010:

- AshAgent leads with: agent-as-first-class-entity, scope-as-DSL,
  eval-first design, Jido-backed runtime.
- `ash_ai` differs in mental model and ecosystem.
- Co-existence is fine. Folding into `ash_ai` is not the v0.1.0 goal.
- Positioning depends on `ash_ai`'s current state; verify before
  publishing the README (open question item #1).

### D13. Telemetry layering with Jido OTel

- AshHarness emits `[:ash_harness, …]` `:telemetry` events.
- AshHarness attaches `ash_harness.*` attributes to the **active** Jido
  OTel span at the moment of emission.
- We do not create our own root spans; Jido already has a complete
  span hierarchy.
- Subscribers see one trace tree.

## Risks / Trade-offs

[Risk: `jido_composer` API drift] → Pin to `~> 0.5`. Schedule a Jido
compat audit before each major Jido release. The harness's gate
pipeline and Ash integration are decoupled enough that swapping
runtimes would be a focused refactor — not v0.1.0 design work, but
worth keeping the boundary clean.

[Risk: training-time research has gaps in current `ash_ai`,
`jido_composer`, and τ-bench shape] → Open questions #1–#3 in
`design/implementation/open-questions.md`. Verify before any external
publication. Prefer reading source over hexdocs cache when the runtime
contract is involved.

[Risk: progressive disclosure adds reasoning load (agent must pick
which skill to load)] → Mitigation: short, hint-rich resource
summaries; reachability map shows traversable connections; eval
scenarios in v0.1.0 measure load-then-act efficiency via
`report :trajectory`.

[Risk: τ-bench port drifts from upstream τ-bench leaderboard
methodology] → Document the methodology delta in the port's README.
Map gate-pass-rate to τ-bench's metric explicitly. Not a goal to
match exact numbers — goal is a credible, reproducible test.

[Risk: text-only delegation is wasteful when both agents are in the
same trust zone] → Acknowledged. Document. Ship cautious; revisit in
v0.2 with two-tier mode if eval data shows the cost is high.

[Risk: per-turn mutation budget is novel and surprises users] →
Document in the agent DSL doc and the rendered system prompt
("Operating limits: at most N mutations per turn"). Lean conservative
default (10); users can raise it explicitly.

[Risk: tool name collisions across resources with the same suffix] →
Verifier raises with a specific message and suggests the `as: "..."`
alias. Add the alias DSL only if a real test case demands it; defer
to v0.2 if no one hits it.

[Risk: the eval framework's judge model is the same family as the
agent's model → self-preference bias] → Document the recommendation
to use a different model family for the judge. The framework will
not enforce this; it surfaces it.

[Risk: hot-reload during dev leaves stale orchestrator references] →
Document: restart the IEx node or call `new_session/2` again. Don't
auto-detect; it's a dev concern. Phoenix code reloader users can
hook session invalidation if they want.

## Migration Plan

This is a greenfield change against a placeholder scaffold. There is
nothing to migrate.

**Deployment sequence (matches `design/implementation/phases.md`):**

0. Wire deps in `mix.exs`. Half a day.
1. Static introspection (Resource, Domain, Agent extensions;
   reachability; canonical schema; renderers; verifiers; test
   resources). 5–7 days.
2. Context renderer (initial text + per-resource detail; token-budget
   truncation; cache). 2–3 days.
3. Tool generation (compile-time emission; runtime dynamic API;
   BFCL-style schema tests). 3–4 days.
4. Harness runtime (session, gates, action executor, orchestrator
   factory, run/resume; repair loop formatter). 5–7 days.
5. Delegation + telemetry. 2–3 days.
6. Eval framework. 3–4 days.
7. τ-bench airline port (child package). 5–8 days.
8. Docs, examples, hex publication. 2–3 days.

**Rollback:** v0.1.0 is the first release. Pre-publication, rollback
is `git revert` / `git reset`. Post-publication, retract the hex
release and ship a fix.

## Open Questions

The full open-questions list is in
`design/implementation/open-questions.md`. The five most blocking for
implementation:

1. Verify the current state of `ash_ai` on GitHub before publishing
   the README and ADR 0010 (#1 in design open questions).
2. Verify `jido_composer` API surface details:
   `Skill.assemble/2` return shape, suspension/resume plumbing,
   `LLMStub` exposure, model-string format, OTel span hierarchy
   (#2 in design open questions). Spike before Phase 1 finishes.
3. Fetch the current τ-bench airline schema, policy text, and task
   suite (#3 in design open questions). Required before Phase 7
   begins.
4. Confirm the path for `set_attributes/1` on the active OTel span
   from inside a Jido tool-call context (#14 in design open
   questions). May affect the telemetry-events spec implementation.
5. Confirm that `Jido.Action.run/2` may return a halt directive (or
   document the workaround) for the confirmation gate (#11 in design
   open questions).

These are tracked as work items in `tasks.md` (Phase 0 — pre-flight).
