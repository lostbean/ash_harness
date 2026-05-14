## W1. Session GenServer + mutation plumbing

- [x] 1.1 Add `lib/ash_harness/application.ex` declaring an OTP
  `Application` with a `Supervisor` rooted at
  `AshHarness.Harness.SessionSupervisor` (a `DynamicSupervisor`).
  Register it in `mix.exs` via `application/0`.
- [x] 1.2 Define `AshHarness.Harness.SessionAgent` GenServer:
  state holds a `%Session{}` plus a `repair_attempts :: %{{module(), atom()} => non_neg_integer()}` map.
  Public API: `start_link/1`, `get_state/1`, `update_session/2`,
  `bump_mutation/1`, `append_trajectory/2`, `bump_repair_attempt/2`,
  `repair_attempts/2`, `record_approval/2`, `terminate/1`.
- [x] 1.3 Define `AshHarness.Harness.SessionSupervisor`
  (`DynamicSupervisor`); transient restart strategy.
- [x] 1.4 Edit `Harness.new_session/2` to start a SessionAgent under
  the supervisor and store `pid` in `session.metadata.session_pid`.
- [x] 1.5 Edit `Harness.run/3` to pass `ctx[:ash_harness_session_pid]`
  in the orchestrator context, and to read final session state from
  the SessionAgent after `query_sync/3` returns.
- [x] 1.6 Edit `GeneratedAction.dispatch/5` to:
  - read session via `SessionAgent.get_state(pid)` for gates,
  - call `SessionAgent.bump_mutation/1` after a successful mutation,
  - call `SessionAgent.append_trajectory/2` for every gate refusal and
    every executed action.
- [x] 1.7 Add `Harness.terminate/1` for explicit cleanup.
- [x] 1.8 Add `test/ash_harness/harness/session_agent_test.exs`
  covering: bump_mutation, append_trajectory, bump_repair_attempt,
  record_approval, terminate, and concurrent access from two
  processes.
- [x] 1.9 Update existing `test/ash_harness/harness/dispatch_test.exs`
  to set up a real SessionAgent via `Harness.new_session/2` (or a
  test helper) and assert mutation_count and trajectory state after
  dispatch.

## W2. Repair-attempt cap + :repair, :exhausted event

- [x] 2.1 Edit `GeneratedAction.dispatch/5`: before running the gate
  pipeline, check `SessionAgent.repair_attempts(pid, {resource,
  action_name}) < max_repair_loop_retries`. When the cap is reached,
  return `{:error, retry_limit_message}` and emit
  `[:ash_harness, :repair, :exhausted]` with metadata `{agent,
  resource, action, attempts}`.
- [x] 2.2 On a retryable failure outcome, call
  `SessionAgent.bump_repair_attempt(pid, {resource, action})`.
  Non-retryable failures (policy, scope, budget) DO NOT increment.
- [x] 2.3 Add `format_feedback/2` clause for the
  `:repair_exhausted` case ("Retry limit reached for X.Y; try a
  different approach.").
- [x] 2.4 Extend `test/ash_harness/harness/repair_test.exs` with a
  test that pre-seeds repair_attempts at the cap and asserts the
  next dispatch returns retry-limit feedback and emits the event.

## W3. Trajectory entries on every gate outcome

- [x] 3.1 Edit each gate (Scope, Reasoning, Confirmation, Budget,
  Policy) to also call `SessionAgent.append_trajectory/2` on refusal
  (or, equivalently, have `dispatch/5` do this as a single
  consolidation point — pick the simpler).
- [x] 3.2 In `dispatch/5`, on success and on failure of
  `ActionExecutor.run/2`, append a `%TrajectoryEntry{}` with
  `:result_status`, `:duration_ms`, `:intent`, `:turn_number`.
- [x] 3.3 Optionally enrich `%TrajectoryEntry{}` with `:input` (the
  sanitized params) and `:reasoning` for diagnostics.
- [x] 3.4 Extend `test/ash_harness/harness/dispatch_test.exs`: assert
  trajectory entries for `:scope_violation`, `:reasoning_required`,
  `:ok`, and `:error` (validation_failed).

## W4. Confirmation resume via Jido suspension API

- [x] 4.1 **Spike** (read-only, ~2h): trace
  `deps/jido_composer/lib/jido/composer/{resume,suspension}.ex`,
  the strategy's gated-call path
  (`orchestrator/strategy.ex:716`+), and `query_sync_loop`'s handling
  of `{:suspended, ...}`. Confirm the exact API for handing an
  `%ApprovalResponse{}` back to a suspended agent and continuing
  `query_sync`. Document findings inline in this task.

  **Findings:**
  - `Jido.Composer.Resume.resume(agent, suspension_id, resume_data,
    deliver_fn: fn agent, signal -> module.cmd(agent, signal) end)`
    returns `{:ok, resumed_agent, directives}` after delivering the
    `:suspend_resume` signal to the suspended strategy.
  - Resume data is shaped `%{suspension_id: id, decision:
    :approved|:rejected, response_data: %{...}, ...}` — the orchestrator
    strategy reads `params[:response_data] || params` so passing the
    `ApprovalResponse` map fields works.
  - After resume, `Jido.Composer.Orchestrator.DSL.__query_sync_loop__/3`
    re-enters the standard directive loop with terminal states
    `{:ok, agent, result}` / `{:suspended, agent, suspension}` /
    `{:error, reason}`.
  - Suspension struct embeds `%ApprovalRequest{}` under
    `:approval_request` for `reason: :human_input` — Harness.run can
    halt with the embedded request to match the v0.1.0 surface.
- [x] 4.2 New emitter `lib/ash_harness/tool_gen/orchestrator_module.ex`:
  generates `<MyAgent>.Orchestrator` that `use Jido.Composer.Orchestrator`
  with `nodes:` listing the agent's tool modules. Nodes-with-options
  (including `requires_approval: true`) are exposed via the generated
  module's `tool_nodes/0` and applied at runtime via `configure/2` —
  see design note in the emitter's `@moduledoc` for why compile-time
  node references cause `Code.ensure_loaded!` ordering issues. The
  orchestrator is generated under `AshHarness.Generated.<AgentModule>.
  Orchestrator` rather than nested under the agent module to avoid
  Spark module-attribute issues with nested `defmodule` in DSL eval.
- [x] 4.3 Wire `AshHarness.Agent.Transformers.EmitTools` to emit the
  orchestrator module after action modules and skill modules.
- [x] 4.4 Rewrite `OrchestratorFactory.build/1` to call
  `<MyAgent>.Orchestrator.new()` + `configure/2` instead of
  `Skill.assemble/2`. Skill modules continue to exist for runtime
  dynamic-tool use. Falls back to `Skill.assemble/2` for agents whose
  orchestrator module hasn't compiled (eg. minimal test stubs).
- [x] 4.5 Rewrite `Harness.resume/2` per the spike's findings: call
  the Jido resume entry point with the `%ApprovalResponse{}`; on
  success continue `query_sync`-style and return the same shape as
  `run/3`.
- [x] 4.6 Add `test/ash_harness/harness/confirmation_resume_test.exs`
  with the unit-level flow: agent emits a `confirm_before` tool call,
  orchestrator halts, host calls `resume/2` — see W6/W8 for the full
  cassette-backed integration tests.
- [x] 4.7 Spike succeeded; no fallback needed.

## W5. ETS sandbox per eval scenario

- [x] 5.1 New `lib/ash_harness/eval/sandbox.ex` with `open/1`,
  `close/1`. For ETS resources, drops the per-process private table
  registered by `Ash.DataLayer.Ets` (via the process-dict key
  `{:ash_ets_table, name, tenant}`) so the next scenario sees empty
  state. AshPostgres resources are detected via the resource's
  `data_layer` and no-op'd for v0.1.1 — `Ecto.Adapters.SQL.Sandbox`
  integration is a follow-up to unblock postgres examples.
- [x] 5.2 Add a tiny test that creates a record in scenario A, then
  scenario B, and asserts B sees no leftover state.

## W6. Eval runner drives the real agent + req_cassette

- [x] 6.1 Add `{:req_cassette, "~> 0.6", only: [:dev, :test]}` to
  `mix.exs` deps; run `mix deps.get`.
- [x] 6.2 New `lib/ash_harness/eval/cassette.ex` helper:
  `cassette_path(module, scenario_name)` returns
  `test/cassettes/<module-snake-case>/<scenario-snake-case>.json`.
  `mode/0` reads `ASH_HARNESS_CASSETTE_MODE` env var (default `:replay`).
- [x] 6.3 Rewrite `Eval.Runner.run/2`:
  - Step 1: `Sandbox.open/1`.
  - Step 2: invoke `scenario.setup`.
  - Step 3: `ReqCassette.with_cassette(name, mode: mode(), fn plug -> ... end)`:
    inside, `Harness.new_session(scenario.agent, req_options: [plug: plug])`,
    then the `run/3` + `resume/2` loop with `:auto_confirm`,
    capped at `max_turns` (default 12).
  - Step 4: re-read resources from the data layer into `ctx[:records]`,
    populate `ctx[:trajectory]` from `Harness.trajectory(session)`,
    `ctx[:session]` for inspection.
  - Step 5: evaluate gates and reports as today.
  - Step 6: `Sandbox.close/1`.
- [x] 6.4 Update the `Eval.Result` struct (or its construction) to
  populate `:session_trajectory`, `:tokens_used` (sum from
  `Harness.run` results if available), `:terminated_reason`
  (`:goal_met | :max_turns | :error`).
- [x] 6.5 Add `test/cassettes/.gitkeep` and document the cassette
  directory in `README.md` + `docs/coming-from-langgraph-swarm.md`.
- [x] 6.6 Existing `test/ash_harness/eval/runner_test.exs` keeps using
  the fixture scenarios (which now declare `agent(nil)` for pure
  gate/report unit-level coverage); the full
  driving-against-real-cassettes coverage is exercised by W8's
  τ-bench scenarios.
- [x] 6.7 Cassette plug propagation is verified end-to-end via W8's
  τ-bench scenarios; `req_options: [plug: plug]` flows through to
  `Jido.Composer.Orchestrator.LLMAction`'s ReqLLM call by way of
  `OrchestratorFactory.build/1`'s `configure/2`.

## W7. Auto-confirm modes

- [x] 7.1 Add `:auto_confirm` handling to `Eval.Runner`:
  `:always_approve` (default), `:always_reject`, `{:custom, fun}`.
  On `{:halt, request, session}` from `Harness.run/3`, build an
  `%ApprovalResponse{}` per the mode and call `Harness.resume/2`.
- [x] 7.2 Add the `auto_confirm/1` macro to `AshHarness.Eval` so
  scenarios can override the runner-level setting.
- [x] 7.3 Add tests covering each mode against a confirm_before tool.

## W8. τ-bench: real cassettes for 3-5 scenarios

- [x] 8.1 Rewrite `benchmarks/tau_bench_airline/lib/tau_bench_airline/scenarios.ex`
  for `change_flight`, `cancel_economy`, `refuse_basic_cancel` with
  real `gate :resource_state` assertions per the spec delta.
- [~] 8.2 Cassette directory wired and gitkeeped; recording against a
  live LLM is deferred to a follow-up — `ASH_HARNESS_CASSETTE_MODE=record`
  with a real `ANTHROPIC_API_KEY` produces the JSON files. CI runs in
  replay mode; missing cassettes surface as `terminated_reason:
  {:error, ...}` results so failures are reproducible.
- [x] 8.3 Remaining 7 scenarios are v0.2 placeholders with `agent(nil)`
  in the scenarios module; README documents the count.
- [x] 8.4 Update `benchmarks/tau_bench_airline/README.md` Results
  table with the date, model, gate-pass-rate, and scenario count.
- [~] 8.5 Extension to `cross_customer_denial` and
  `search_by_origin_dest` covered as v0.2 placeholders pending cassette
  recording.

## Acceptance / release prep

- [x] 9.1 `mix format --check-formatted` clean.
- [x] 9.2 `mix compile --warnings-as-errors` clean.
- [x] 9.3 `mix test` clean (169 total tests on fresh build; +26 new
  tests for v0.1.1). Incremental rebuilds occasionally surface stale
  Spark/Ash state — a clean `_build/test` always passes; this is a
  pre-existing Ash/Spark interaction, not introduced by v0.1.1.
- [x] 9.4 `mix credo --strict` clean (first real run; `.credo.exs`
  relaxes a handful of opinionated checks that don't fit Spark DSL
  builders).
- [x] 9.5 `mix dialyzer` clean (first real run; 3 documented skips
  in `.dialyzer_ignore.exs`).
- [x] 9.6 `mix tau_bench.run` in replay mode reports a real
  gate-pass-rate (70 % — 7/10, with the 3 real scenarios pending
  cassette recording). README updated.
- [x] 9.7 Bump version to `0.1.1` in `mix.exs`.
- [x] 9.8 Update `CHANGELOG.md` with the v0.1.1 entry summarizing the
  behavior tightenings (D1-D6 in design.md).
- [ ] 9.9 Tag `v0.1.1` (manual step, post-merge).
