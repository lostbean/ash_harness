# Changelog

All notable changes to this project will be documented in this file.

## v0.1.1 — Runtime completion

### Changed (behavior tightenings — see ADRs D1–D6 in
`openspec/changes/complete-runtime-v0-1-1/design.md`)

- **Session is now a supervised GenServer** (D1). Mutable per-turn
  state — `mutation_count`, `trajectory`, `repair_attempts`,
  recorded `approvals` — lives in `AshHarness.Harness.SessionAgent`
  under `AshHarness.Harness.SessionSupervisor`. The pid lands in
  `session.metadata.session_pid` and travels with the orchestrator
  context as `ctx[:ash_harness_session_pid]`. The `%Session{}` struct
  returned to host code is a snapshot at turn boundaries.
- **`mutation_count` now reflects actual mutations** (was always 0
  unless the host manually incremented). The Budget gate sees the
  current value before each tool call and bumps after a successful
  mutating action.
- **`trajectory/1` returns the full per-tool-call sequence** (was
  delegation-only). Every gate refusal (`:scope_violation`,
  `:reasoning_required`, `:budget_exceeded`, `:policy_denied`,
  `:confirmation_required`) and every executed action gets a
  `%TrajectoryEntry{}` with `:result_status`, `:duration_ms`,
  `:intent`, and `:turn_number`.
- **Repair-attempt cap is enforced per (resource, action)** (D-related,
  see `repair-loop` spec). Retryable failures (validation,
  `:reasoning_required`) consume an attempt; non-retryable ones
  (policy, scope, budget) do not. Hitting the cap returns
  retry-limit feedback to the LLM and emits
  `[:ash_harness, :repair, :exhausted]`.
- **`Harness.resume/2` hands the response straight into Jido's
  suspension machinery** (D6) via `Jido.Composer.Resume.resume/4` +
  `query_sync_loop`. No more host-side `run/3` replay. Falls back to
  v0.1.0 behavior when no `%Suspension{}` is pending.
- **Per-agent `Orchestrator` module** generated at compile time (D2).
  Lives under `AshHarness.Generated.<AgentModule>.Orchestrator`.
  `OrchestratorFactory.build/1` calls `new()` + `configure/2` with
  the rendered system prompt, model, and tool nodes (with
  `requires_approval: true` for `confirm_before` actions).
- **`Eval.Runner.run/2` drives a real agent end-to-end** (D3).
  `Sandbox.open/1` → `scenario.setup` →
  `ReqCassette.with_cassette/3` → `Harness.run/3` + `resume/2` loop
  (auto-confirm modes from D4, default `:always_approve`) →
  `Harness.trajectory(session)` into the eval ctx.
- **ETS sandbox per scenario** (D5). `AshHarness.Eval.Sandbox.open/1`
  drops the per-process private table for each ETS-backed resource
  so scenarios don't share state. AshPostgres integration is a
  follow-up.
- **`req_cassette` integration for default `mix test`** — cassettes
  live at `test/cassettes/<module-snake-case>/<scenario-snake-case>.json`;
  mode controlled by `ASH_HARNESS_CASSETTE_MODE` (`replay` default,
  `record`, `bypass`).
- **`auto_confirm/1` macro on `AshHarness.Eval`** — scenarios can
  override the runner-level `:auto_confirm` setting.
- **τ-bench airline scenarios driven end-to-end via cassettes**:
  `change_flight`, `cancel_economy`, `refuse_basic_cancel` with real
  `gate :resource_state` assertions on final state. Remaining seven
  scenarios remain in placeholder form pending v0.2 cassette
  recording.

### Added

- `AshHarness.Harness.terminate/1` — explicit cleanup of the
  SessionAgent backing a session.
- `AshHarness.Eval.Sandbox.{open,close,open_for_agent,reset_resource}/1`.
- `AshHarness.Eval.Cassette.{cassette_path/2,mode/0}` helper.
- `[:ash_harness, :repair, :exhausted]` telemetry event.

### Telemetry

- `[:ash_harness, :repair, :exhausted]` fires with measurements
  `%{attempts: n}` and metadata
  `%{agent, resource, action, request_id}` when the per-(resource,
  action) repair cap is reached.

### CI / tooling

- `mix credo --strict` and `mix dialyzer` ran clean for the first
  time; `.credo.exs` relaxes a handful of opinionated checks that
  don't fit Spark DSL builders, and `.dialyzer_ignore.exs` lists
  three intentional skips with comments.
- `mix.exs` now declares an `Application` module with the
  `SessionSupervisor` started under `AshHarness.Supervisor`.

### Behavior changes downstream consumers will see

1. `session.mutation_count` after `run/3` reflects actual mutations.
2. `Harness.trajectory(session)` returns a populated list.
3. `Harness.resume/2` returns `{:ok, reply, session}` only after the
   agent finishes the turn (when a Jido suspension is pending).
4. Repair attempts are capped per (resource, action).
5. The orchestrator strategy is the primary source of HITL halts;
   `AshHarness.Harness.ConfirmationGate` is the defensive secondary.

### Out of v0.1.1

- Progressive disclosure via `DynamicAgentNode` (still v0.2).
- AshPostgres sandbox integration (follow-up).
- Full ~50-scenario τ-bench coverage (v0.2 target).
- Two-tier delegation with structured returns.
- Streaming, multi-model routing, persistent memory.

## v0.1.0 — Initial release

### Added

- `AshHarness.Resource` Spark DSL extension for agent-facing
  annotations on Ash resources (`agent_annotations` section with
  `description`, `hint`, `traversable`, `hidden_attributes`).
- `AshHarness.Domain` Spark DSL extension for domain-level vocabulary
  (`agent_domain` section with `description` and `term` entries).
- `AshHarness.Agent` DSL with `identity`, `scope`, `behavior`,
  `delegates_to`, and `constraints` sections.
- Compile-time `Jido.Action` module per scoped action and
  `Jido.Composer.Skill` per scoped resource.
- Canonical schema artifact (`AshHarness.Schema.Canonical`) with
  Anthropic, OpenAI, and MCP renderers; deterministic Ash-type to
  JSON-Schema mapping.
- Context renderer (`AshHarness.ContextRenderer`) producing initial
  system prompt and per-resource detail strings, with token-budget
  truncation and per-(agent, actor) ETS caching.
- Harness runtime: session lifecycle, gate pipeline (scope, reasoning,
  confirmation, budget, policy), action executor dispatching to
  `Ash.read/create/update/destroy/run_action`, public
  `new_session/2`, `run/3`, `resume/2`, `trajectory/1`,
  `mutation_count/1` API.
- Repair loop (`AshHarness.Harness.Repair`) — formats Ash errors as
  LLM feedback; classifies retryable vs terminal.
- Cross-agent delegation (`AshHarness.Delegation`) with depth limit
  (default 3) and text-only return.
- Telemetry (`AshHarness.Telemetry`) emitting `[:ash_harness, …]`
  events and attaching `ash_harness.*` attributes to active OTel
  spans.
- Eval framework (`use AshHarness.Eval`) with `gate :resource_state` /
  `gate :invariant` (pass/fail) and `report :trajectory` /
  `report :qualitative` (diagnostic) — no composite score.
- `mix ash_harness.eval` Mix task.
- τ-bench airline-domain port as a child package
  (`benchmarks/tau_bench_airline/`) with 10 scenarios, JSON fixtures,
  multi-turn runner, and `mix tau_bench.run` task.
- Documentation: README quickstart,
  `docs/coming-from-langgraph-swarm.md`,
  `docs/coexistence-with-ash-ai.md`, examples directory.

### Decisions

This release implements 10 architectural ADRs (see `design/adrs/`):

1. Runtime is `jido_composer`, not a custom loop.
2. Eval scoring is pass/fail gates + diagnostic reports, not weighted average.
3. Ralph Loop is renamed to Repair Loop.
4. Delegation returns text only (anti-corruption boundary).
5. Tool generation is hybrid (compile-time + runtime).
6. One canonical schema, three renderers.
7. Progressive disclosure via per-resource Skills + DynamicAgentNode
   (deferred to v0.2 in this release; see Phase 0 verification note
   in `openspec/changes/bootstrap-ash-harness-v0-1-0/tasks.md`).
8. Library is data-layer-agnostic; ETS is the default.
9. `mutation_count` is per-turn, novel to AshHarness.
10. Position vs `ash_ai` is "alternative with different opinions".

### Out of v0.1.0

Deferred to v0.2 or later: streaming, multi-model routing, persistent
agent memory, Phoenix LiveView UI, MCP server router (the renderer
ships), two-tier delegation (structured returns within trust zone),
full ~50-task τ-bench airline coverage, progressive disclosure with
`DynamicAgentNode`.
