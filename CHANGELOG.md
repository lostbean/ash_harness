# Changelog

All notable changes to this project will be documented in this file.

## v0.1.2 — Audit follow-up

Closes the ten gaps surfaced by the 2026-05-15 design-vs-implementation
audit. No new feature surface; every change is either a correction, a
hole closure, or doc alignment. See
`openspec/changes/audit-followup-v0-1-2/` for the full proposal /
design / tasks record.

### Added

- **Structured error tree** under `lib/ash_harness/errors/`: seven
  `defexception` modules built on `Splode` —
  `AshHarness.Errors.{ScopeViolation, PolicyDenied, ValidationFailed,
  MutationLimitExceeded, ReasoningRequired, DelegationNotPermitted,
  DelegationDepthExceeded}`. All five gates and `Delegation.initiate/4`
  now return these instead of `{:error, atom()}` reasons.
  `AshHarness.Errors.classify/1` maps a struct to its Splode class atom.
- **Delegation skill wired to the LLM** (`lib/ash_harness/delegation/
  skill.ex`). A dynamic `delegate(target, question)` Jido.Action is
  appended to the orchestrator's tool list whenever the agent's
  `delegates_to` block is non-empty. The skill resolves `target` against
  the agent's declared `:as` aliases (case-insensitive), dispatches
  through `AshHarness.Delegation.initiate/4`, and returns the
  delegate's reply text. Unknown aliases produce a tool-result error
  listing the valid set. The skill forwards
  `[:req_options, :temperature, :max_tokens, :max_iterations]` from
  the parent session's options to the child so LLMStub-backed tests
  see the same stub on both sides.
- **`as:` alias entry on `delegate`** (`lib/ash_harness/agent/dsl.ex`).
  `delegate MyApp.Foo, as: "foo", for: "..."` — the `as:` value is what
  the LLM passes to the skill. A new verifier
  (`AshHarness.Agent.Verifiers.DelegateAliasesUnique`) rejects duplicate
  aliases (case-insensitive) at compile time.
- **`:request_id` correlation** on every telemetry event emitted within
  a single `GeneratedAction.dispatch/5` call. Generated as a UUID v4 at
  dispatch entry; surfaces as the `ash_harness.request.id` OTel
  attribute and as `:request_id` in every gate, action, repair, and
  delegation event for that dispatch.
- **Four `:checked` gate pass-events** fire on every gate evaluation,
  whether the gate passed or refused: `[:ash_harness, :scope, :checked]`,
  `[:ash_harness, :reasoning, :checked]`,
  `[:ash_harness, :budget, :checked]`,
  `[:ash_harness, :policy, :checked]`. Metadata carries
  `passed: boolean` and the shared `:request_id`. Listeners can now
  compute pass-rates without OTel span sampling.
- **`%TrajectoryEntry{data: %{}}` field** for payload data on entries
  that have it (today: delegation, which populates
  `%{reply_text, target_trajectory_id}`). `:metadata` keeps its
  OTel-encoder role; `:data` is the user-facing payload bucket.
- **`AshHarness.Delegation.Result` struct** —
  `%{reply_text, target_trajectory_id, target_trajectory, status}` used
  internally so telemetry, trajectory, and skill return all share one
  shape.

### Changed

- **Delegation module split** into a subdirectory:
  `lib/ash_harness/delegation/initiate.ex` (the cross-agent boundary
  crossing, formerly inlined in `delegation.ex`),
  `delegation/result.ex` (new internal struct), and
  `delegation/skill.ex` (the new Jido.Action). The public
  `AshHarness.Delegation.initiate/4` keeps its arity; it's now a thin
  re-export of `AshHarness.Delegation.Initiate.run/4`.
- **`repair:exhausted` measurement key renamed** from `:attempts` to
  `:total_attempts` per the layer-11 telemetry spec. Listeners reading
  the old name need updating.
- **Telemetry metadata enriched** on ten existing events to match
  `design/layers/11-telemetry.md`:
  - `confirmation:approved` gains `:respondent`, `:duration_ms`
  - `confirmation:rejected` gains `:respondent`
  - `policy:denied` gains `:ash_error_class`
  - `action:executed` gains `:records_returned` (reads),
    `:records_changed` (mutations), and `:error_class`
  - `delegation:started` / `delegation:ended` gain `:depth`,
    `:target_trajectory_id`, `:request_id`
  - `eval:scenario:stop` gains `:agent`, `:gates_passed`,
    `:gates_failed`
  - `eval:gate:checked` gains `:scenario`, `:passed`
  - `eval:report:computed` gains `:scenario`, `:observations`
- **`SessionAgent.init/1` stamps `metadata.session_pid = self()`** so
  code that only has the `%Session{}` snapshot (e.g. the delegation
  skill calling `Delegation.Initiate.run/4` after `get_state`) can
  reach the SessionAgent without an out-of-band pid handle.
- **CLAUDE.md "Project state" rewritten** to reflect v0.1.2 reality
  (phases 1–6 complete, ~90 modules, design docs are reference). The
  architecture pointers, ADR shortcuts, and house rules stayed put.
- **README.md status section bumped** to call out v0.1.2 as the
  current stable release with the audit-followup highlights.
- **Design docs realigned to code** for two API signatures:
  - `AshHarness.Tool.dynamic/2` returns `AshHarness.Tool.t()` (a
    wrapper struct), not `Jido.Action.t()`; takes
    `(keyword(), keyword())`.
  - `AshHarness.ContextRenderer.render_resource/3` takes
    `(agent, resource, actor)` — the design's `opts` form is
    deferred to v0.2. `resource_summary/2` is removed from
    `public-api.md` (it was never implemented; the
    `RenderedContext.resource_details` map covers the use case).
- **Six open questions resolved** in
  `design/implementation/open-questions.md` (Q#2, Q#4, Q#5, Q#7, Q#11,
  Q#14) with `file:line` references to where they're settled in code;
  nine others re-audited.

### Fixed

- **`repair:feedback` no longer hardcodes `attempt: 1`**
  (`generated_action.ex:314`). The real per-(resource, action)
  attempt count from the dispatch local is now threaded into the
  emit. Repair telemetry consumers see `attempt: 1` then `attempt: 2`
  etc. as the LLM retries.

### Breaking

- **Gate return shape**:
  `{:error, :scope_violation | :policy_denied | :budget_exceeded |
  :reasoning_required | :validation_failed}` is replaced by
  `{:error, %AshHarness.Errors.<Struct>{}}`. The public
  `AshHarness.Harness.run/3` return shape is unchanged (it's already
  `{:ok | :halt | :error, _, session}`); the breakage is for code that
  calls a gate's `check/1`/`check/2` directly or pattern-matches the
  pre-execution result. `Repair.format_feedback/2` now pattern-matches
  on the structs. Migration: replace atom matches with struct matches
  on the same field set.
- **`delegate ..., as: "..."` is now required**. Agents that declare
  `delegates_to` without an `:as` alias on each entry will fail to
  compile with a verifier error. Migration: add an `as:` alias to
  every `delegate` (short, case-insensitive — what the LLM passes to
  the skill). The compile error names the offending delegate.
- **`session.metadata.approvals` map shape** is now a richer record
  (`%{decision, respondent, recorded_at}`) instead of a bare decision
  atom. Code that read approvals straight off the session before
  v0.1.2 needs to look at `entry.decision` (or `entry` itself, for
  legacy paths the gate still tolerates the atom form).
- **`repair:exhausted` `:attempts` → `:total_attempts`** — see
  Changed.

### Known issues

- The `delegate(..., for: "...")` DSL emits a benign Spark-time
  warning: `for/1 conflicts with Elixir special forms, the import has
  been discarded`. The `for:` value is still captured correctly (it's
  a keyword arg, not the `for` import). Will be silenced when we
  rename the option in v0.2; harmless in the meantime.

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
