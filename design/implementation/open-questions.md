# Open Questions

These need answers before or during implementation. Ranked by urgency.

## Must answer before Phase 1

### 1. Verify the `ash_ai` situation

ADR 0010 is based on training-time knowledge of `ash_ai`. Before
publishing the README, check:

- The current feature set of `ash_ai` on GitHub.
- Whether they've added agent-DSL features that overlap heavily.
- Whether the maintainers would be receptive to a contribution path
  for AshHarness's distinguishing features.

If the ecosystem has shifted, revisit the positioning.

### 2. Verify Jido Composer API surface details

**RESOLVED (v0.1.1, 2026-05-15).** All five sub-questions are settled
in `lib/ash_harness/harness.ex` (lines 100–132 build the orchestrator
via `Jido.Composer.Skill.assemble/2` and `configure/2`; lines 423–438
use `Jido.Composer.Orchestrator.DSL.__query_sync_loop__/3` directly for
the resume path because `Composer.Resume.resume/4`'s `deliver_resume/4`
internal step doesn't fit our suspension shape) and in
`lib/ash_harness/harness/orchestrator_factory.ex` (model-string format
`"anthropic:claude-sonnet-4-5"`, etc.). `LLMStub` is publicly exposed —
the τ-bench airline runner depends on it. OTel attachment via
`OpenTelemetry.Tracer.set_attributes/1` works in-line within the
tool-call context (see `lib/ash_harness/telemetry.ex:152`); we attach
to the active Jido span without spawning our own.

### 3. τ-bench current shape

**PARTIALLY RESOLVED (v0.1.1, 2026-05-15).** The 10-scenario τ-bench
airline port lives at `benchmarks/tau_bench_airline/` with Ash
resources (`User`, `Flight`, `Reservation`, …), the airline policy
document (`benchmarks/tau_bench_airline/priv/policy.md`), and JSON
fixtures replayed from the upstream task suite. Three scenarios
(`change_flight`, `cancel_economy`, `refuse_basic_cancel`) are driven
end-to-end via cassettes with real `gate :resource_state` assertions;
**still open**: the remaining seven scenarios are placeholders pending
cassette recording (v0.2 target), and the τ-bench %-score parity
question (Q#19) is unmet.

## Must answer during Phase 1

### 4. Spark version compatibility

**RESOLVED (v0.1.0, 2026-05-15).** Spark v2.x's `default_extensions`
mechanism works as the spec assumed. `lib/ash_harness/agent.ex` and
`lib/ash_harness/agent/dsl.ex` use the standard pattern with
`Spark.Dsl.Extension`, `Spark.Dsl.Section`, and `Spark.Dsl.Entity`
without any v2.x-specific workarounds. The agent, resource, and domain
DSLs all compile under Spark `~> 2.0` declared in `mix.exs`.

### 5. How do we propagate session into generated `Jido.Action.run/2`?

**RESOLVED (v0.1.1, 2026-05-15).** The SessionAgent's pid travels
through the orchestrator's tool-call context as
`ctx[:ash_harness_session_pid]` (see `lib/ash_harness/harness.ex:102`).
Generated actions call `SessionAgent.get_state(pid)` to pull the
current `%Session{}` snapshot. v0.1.2 additionally stamps
`metadata.session_pid = self()` in `SessionAgent.init/1`
(`lib/ash_harness/harness/session_agent.ex:141`) so code paths that
only have a snapshot (e.g. `Delegation.Initiate.run/4` invoked from
`Delegation.Skill`) can still reach the GenServer. No process
dictionary, no injector — just `ctx`.

## Must answer during Phase 2

### 6. Token estimation tokenizer

**Still open.** v0.1.0 shipped `byte_size / 4` in
`lib/ash_harness/context_renderer/token_estimate.ex` and no caller has
needed better precision yet (the renderer's only token-budget consumer
truncates whole sections, not tokens). When we add streaming or
finer-grained budget enforcement in v0.2, swap in a behaviour and
ship a `tiktoken`-backed default.

### 7. What does Ash 3.x return when `Ash.can?` returns `:maybe`?

**RESOLVED (v0.1.0, 2026-05-15).** `Ash.can?({resource, action, input},
actor)` returns `true | false | :maybe`. The policy gate at
`lib/ash_harness/harness/policy_gate.ex:91` calls it once per
dispatch and treats `false` as denial; both `true` and `:maybe` pass.
The renderer at `lib/ash_harness/context_renderer.ex:343` mirrors this
— actions for which `Ash.can?({resource, action.name}, actor)` returns
`false` are pre-filtered out of the rendered detail; `:maybe` actions
are kept (we let policy decide at execution time when the real input
is available).

## Must answer during Phase 3

### 8. Resource short-name conflict resolution

**Still open for resources; resolved for delegate aliases.** Delegates
got an explicit `as:` alias DSL in v0.1.2 with a dedicated verifier
(`AshHarness.Agent.Verifiers.DelegateAliasesUnique`) that rejects
duplicates case-insensitively. Resource short-name conflicts (e.g.
`MyApp.A.Order` vs `MyApp.B.Order` both rendering as `order` in the
context) are **still open** — neither the renderer nor the agent DSL
disambiguates today; in practice the canonical schema renders use the
full module name in tool names (`order__place`) so the LLM-facing
surface is unambiguous, but the human-readable text in the system
prompt would benefit from a `display_as:` knob in v0.2.

### 9. Generic action input normalization

**Partially resolved.** Generic actions are supported in the schema
generator (`lib/ash_harness/schema.ex`) and dispatch (the action
executor falls through to Ash's standard input shaping). **Still open
within Q#9**: embedded resources are mapped to a generic `:object` in
`lib/ash_harness/schema/ash_type_mapper.ex:73` rather than being
recursed into. For nested embedded shapes the LLM sees an opaque
`object` schema. Tightening to recursive nested-object schemas is a
v0.2 task.

### 10. Read action filter parameters

**Still open.** v0.1.x exposes read-action arguments to the LLM as
typed scalar params (per the canonical schema). The richer `filter`
map shape, operator menu (`eq`, `lt`, `gt`, `in`, `between`), and
sort/pagination meta-tools described in the spec are deferred to v0.2.
For now read actions only take their explicit argument list; if a
project needs cross-attribute filtering it ships an action that
accepts pre-shaped arguments. Filter DSL is a v0.2 milestone.

## Must answer during Phase 4

### 11. Confirmation flow round-trip

**RESOLVED (v0.1.1, 2026-05-15).** Jido's orchestrator strategy is
now the primary HITL halter; `AshHarness.Harness.ConfirmationGate`
acts as the defensive secondary. `Harness.run/3` calls Jido's loop
and surfaces a `%Suspension{}` if pending; `Harness.resume/2` hands
the `%ApprovalResponse{}` straight to
`Jido.Composer.Orchestrator.DSL.__query_sync_loop__/3` so the
orchestrator continues from its suspension point
(`lib/ash_harness/harness.ex:423–438`). The session's
`metadata.approvals` map records the decision +
`respondent` + `recorded_at` so `ConfirmationGate.check/3` on the
post-resume re-entry sees the satisfied approval.

### 12. How is mutation_count tracked across `run`/`resume`?

**RESOLVED (v0.1.1, 2026-05-15).** Mutation count lives in the
supervised `SessionAgent` GenServer
(`lib/ash_harness/harness/session_agent.ex:159–161`), not in any
checkpointed payload. The `%Session{}` snapshot returned to host code
is rebuilt from the GenServer's state at turn boundaries, and Jido's
suspension/resume threads the SessionAgent pid through `ctx`, so the
count is preserved across `run` → halt → `resume` without depending on
Jido's serialization. The budget gate reads the live value from the
GenServer before each tool call (`harness/budget_gate.ex:22`) and the
session bumps after a successful mutation.

### 13. Hot reload behavior

**Still open as policy; documented as "build a fresh session".** The
session struct's `:jido_orchestrator` field can become stale when the
agent module is recompiled — there's no auto-invalidation. The
documented stance lives in `design/layers/07-harness-runtime.md`
("Hot reload" section): users restart the IEx node or call
`new_session/2` to refresh. For Phoenix apps that hot-reload in dev,
the recommended pattern is to drop sessions on reload (via a
`Phoenix.CodeReloader` hook). A formal API for "invalidate by agent
module" would be a v0.2 nicety; not blocking.

## Must answer during Phase 5

### 14. OTel span attribute attachment

**RESOLVED (v0.1.0, 2026-05-15).** Works as the spec assumed. The
attachment helper at `lib/ash_harness/telemetry.ex:152` calls
`apply(:otel_span, :set_attributes, [...])` against the active span
provided by Jido — it's a no-op when no span is active (so tests
without OTel set up don't crash). The full attribute set listed in
`design/layers/11-telemetry.md` (`ash_harness.agent`,
`ash_harness.resource`, `ash_harness.scope.passed`,
`ash_harness.policy.passed`, etc., plus the v0.1.2 `request.id`)
attaches without needing a child span.

### 15. Telemetry event handlers and crash isolation

Test that a buggy user-attached handler doesn't crash the harness.
Document handler-error policy.

## Must answer during Phase 6

### 16. Eval transactional isolation

**RESOLVED for ETS (v0.1.1, 2026-05-15); still open for Postgres.**
`AshHarness.Eval.Sandbox.open/1` opens a per-process private ETS
table for each ETS-backed resource so scenarios don't share state
(`lib/ash_harness/eval/sandbox.ex`); the runner calls
`Sandbox.open/1` → `scenario.setup` → `with_cassette` →
`Harness.run/3` loop. AshPostgres integration (real DB sandboxing
via `Ash.Test`) is still on the v0.2 follow-up list; the design's
"Postgres: standard `Ash.Test` setup with `:async`" plan stands.

### 17. Judge model cost accounting

**Partially resolved.** `lib/ash_harness/eval/judge.ex` calls the
judge LLM at most once per qualitative report (one batched JSON
response covering every criterion in the block) — that batching cuts
N calls down to one. Default `mix test` doesn't hit the judge (the
runner short-circuits when `judge_model` is unset). Cassette replay
covers cost in the test suite. **Still open**: an explicit
content-addressable cache by `(scenario, criterion,
agent_response_hash)` is not implemented; for nightly real-LLM eval
runs we rely on the cassette store rather than a separate judge
cache. Build a dedicated cache layer if real-LLM eval-suite costs
become a problem.

## Must answer during Phase 7

### 18. τ-bench user simulator: separate process or in-line?

Multi-turn drives a back-and-forth between agent and user-simulator.
Should the simulator run in a separate Jido session, or be a callback
function? In-line is simpler; separate process is closer to τ-bench's
Python implementation.

### 19. τ-bench scoring parity

τ-bench reports a specific %-score format. Confirm we can produce a
comparable number from gate-pass-rate over scenarios.

## Stretch / v0.2 questions

- Two-tier delegation (structured returns within trust zone): when do
  we have enough eval data to inform the design?
- MCP server: build our own router, or contribute upstream to
  `hermes_mcp`?
- Streaming: surface partial responses through `AshHarness.Harness.run/3`?
- Reflexion-style memory across attempts: needed, or does Repair Loop
  handle the cases that matter?
- Tool composition audit logging: detect "individually authorized;
  composition isn't" patterns?
- Per-tenant agent caching to avoid re-rendering context every session?

## Discussion log markers

When answering, replace the question block with a short answer plus a
date and the source (`docs verified`, `spike`, `interview`). Keep the
question doc as a living artifact through v0.1.0.
