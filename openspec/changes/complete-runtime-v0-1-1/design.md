# Design — Complete the Runtime (v0.1.1)

## Context

v0.1.0 is structurally complete: 23 ADRs/interview decisions captured,
the full module tree implemented, 143 tests passing. What's not
complete is the *behavior* — the runtime side of the harness has
several intentional stubs that need to become real to ship a usable
library.

This change addresses **session mutation across tool calls**,
**confirmation resume**, **eval-runner driving real agents**, and
**τ-bench cassette-replayed scenarios**. After this change, the
library can be used to build and evaluate agents end-to-end without
host-application gymnastics.

The four open architectural decisions resolved by this change are
recorded in §"Decisions" below.

## Goals / Non-Goals

**Goals:**

- Session mutation (budget, trajectory, repair counter, approvals)
  during a turn, not just at turn boundaries.
- Confirmation resume that hands the `ApprovalResponse` back to Jido's
  suspension machinery — no re-rolling the LLM turn.
- `Eval.Runner` that drives a real agent via `Harness.new_session` +
  `Harness.run` against `req_cassette`-replayed LLM calls.
- Per-scenario isolation: ETS delete-all per scenario; AshPostgres
  sandbox where applicable.
- τ-bench: at least 3 scenarios with real `gate :resource_state`
  assertions against final state, driven via committed cassettes.
- `mix credo --strict` and `mix dialyzer` clean.

**Non-Goals:**

- Progressive disclosure via `DynamicAgentNode` (ADR 0007, v0.2).
- Two-tier delegation (structured returns within trust zone, v0.2).
- Streaming, multi-model routing, persistent memory (v0.2+).
- A re-recording workflow in CI (cassettes are committed; re-record
  is a local human step gated by an env var).
- Full ~50-scenario τ-bench coverage (v0.2 target).

## Decisions

### D1. Mutable session state lives in a GenServer

A supervised `AshHarness.Harness.SessionAgent` GenServer holds the
mutable parts of the session for the duration of one `Harness.run/3`
turn. The `%Session{}` struct returned to host code is a snapshot at
turn boundaries.

`new_session/2`:
1. Builds the value-typed `%Session{}` exactly as today.
2. Starts a `SessionAgent` child under
   `AshHarness.Harness.SessionSupervisor` (a `DynamicSupervisor`),
   gets back a pid.
3. Stores the pid in `session.metadata.session_pid`.

`run/3`:
1. Passes `ctx = %{ash_harness_session_pid: pid, request_id: ...}` to
   `query_sync/3`.
2. After Jido returns, reads the final state from the GenServer back
   into the `%Session{}` struct.
3. Terminates the GenServer (or keeps it alive for the next turn —
   TBD; see §Open Questions).

`GeneratedAction.dispatch/5`:
1. Reads session via `SessionAgent.get_state(pid)` for every gate.
2. Calls `SessionAgent.bump_mutation/1` after a successful mutation.
3. Calls `SessionAgent.append_trajectory/2` for every gate refusal
   and every executed action.
4. Calls `SessionAgent.bump_repair_attempt/2` after a retryable
   failure; refuses with retry-limit feedback when the cap is hit.

**Alternative considered:** per-turn ETS table keyed by `request_id`.
Rejected — GenServer gives us supervision, introspection, and a
typed API for free; the call-rate is low enough that GenServer
overhead doesn't matter.

**Alternative considered:** mutate the session value through the
Jido tool-call context. Rejected — Jido's `run/2` callback returns
to Jido without our session updates, so we'd lose mutations between
tool calls anyway.

### D2. Per-agent orchestrator module replaces `Skill.assemble/2`

`Skill.assemble/2` doesn't accept node-level options
(`requires_approval: true` in particular). For v0.1.1 we generate, at
agent compile time, a `<MyAgent>.Orchestrator` module that
`use Jido.Composer.Orchestrator, nodes: [...]` where each
`confirm_before` action's node is annotated `{module, requires_approval: true}`.

The new emitter (`AshHarness.ToolGen.OrchestratorModule`) is invoked
from `AshHarness.Agent.Transformers.EmitTools` after the per-action
modules are generated.

`OrchestratorFactory.build/1` then does `agent_module.Orchestrator.new()`
+ `configure/2` with the rendered context as `system_prompt` instead
of calling `Skill.assemble/2`.

Skill modules (`<MyAgent>.Skills.<Resource>`) still emit and remain
useful for `AshHarness.Tool.dynamic/2` and for host applications that
want to assemble agents at runtime from skill lists.

### D3. Eval runner drives the agent via `req_cassette`

`Eval.Runner.run/2`:
1. Opens the sandbox (ETS or AshPostgres).
2. Calls `scenario.setup`, storing setup data in `ctx[:records]`.
3. Resolves the cassette name from
   `{module, safe_name(scenario.name)}`.
4. Wraps the agent execution in `ReqCassette.with_cassette/2`:
   - Builds a session: `Harness.new_session(scenario.agent, req_options: [plug: plug])`.
   - Loops: `Harness.run/3` → on `{:halt, request, session}` →
     materialize an `%ApprovalResponse{}` per `:auto_confirm` →
     `Harness.resume/2` → continue.
   - Stops on `{:ok, reply, session}` or terminal `{:error, _, session}`.
5. Re-reads resource state from the data layer into `ctx[:records]`.
6. Adds `ctx[:trajectory] = Harness.trajectory(final_session)`.
7. Evaluates gates and reports against the populated `ctx`.

Cassette mode is governed by `ASH_HARNESS_CASSETTE_MODE`:
- unset (default): `:replay`, fail loudly on missing cassettes.
- `record`: hits the real LLM, records new interactions.
- `bypass`: hits real LLM without writing — debug only.

### D4. Auto-confirm modes

`Eval.Runner` accepts `:auto_confirm`:
- `:always_approve` (default) — every halt → `%ApprovalResponse{decision: :approved}`.
- `:always_reject` — every halt → `:rejected`.
- `{:custom, fn intent -> :approved | :rejected end}` — host predicate.

The runner loops `run/3` and `resume/2` until the agent reaches a
non-halt outcome or `max_turns` (default 12). Per-scenario override
via a `auto_confirm :always_reject` macro in the scenario block.

### D5. ETS sandbox

For ETS-backed resources, `AshHarness.Eval.Sandbox.reset/1` takes a
list of resource modules and calls `:ets.delete_all_objects/1` on
the (private) table held by `Ash.DataLayer.Ets`. The table name is
derived from `Ash.DataLayer.Ets.Info` (or the resource module name —
we'll use whichever the library exposes stably).

For AshPostgres-backed resources, the sandbox uses
`Ecto.Adapters.SQL.Sandbox.checkout/2` + manual rollback in `setup`.
v0.1.1 covers ETS; AshPostgres is documented as a follow-up to
unblock the postgres examples without blocking ship.

### D6. Confirmation resume via Jido suspension API

Spike output drives the exact API. Hypothesis based on
`deps/jido_composer/lib/jido/composer/{resume,suspension}.ex`:

- The orchestrator's strategy emits a `%Suspend{}` directive with a
  `%Suspension{}` carrying the `%ApprovalRequest{}`.
- `query_sync/3` returns `{:suspended, agent, suspension}`.
- To resume: `Jido.Composer.Resume.resume(agent, response)` (or
  equivalent) injects the `%ApprovalResponse{}`, the strategy
  validates and continues from the suspension point.

`Harness.resume/2` becomes:
1. Update the SessionAgent's `approvals` map.
2. Call the Jido resume entry point with the response.
3. Run the orchestrator until it completes or suspends again.
4. Return `{:ok, reply, session}` / `{:halt, ...}` / `{:error, ...}`.

If the spike reveals the resume API is too primitive (e.g., it only
supports a single suspension type and we need a different shape),
we fall back to the v0.1.0 host-replay approach and explicitly mark
this as a v0.2 task.

## Risks / Trade-offs

[Risk: Jido resume API unsuitable] → Spike first (~2 hours). Concrete
escape hatch: keep `resume/2` as v0.1.0 host-replay but document the
limitation more loudly; doesn't block W1, W2, W3, W5, W6 (partial),
W8 (partial).

[Risk: req_cassette doesn't propagate through ReqLLM into the actual
LLM HTTP request] → Smoke test with a minimal cassette before
scripting τ-bench scenarios. ReqLLM appears to support `:req_options`
in `Jido.Composer.Orchestrator.LLMAction` (confirmed at
`deps/jido_composer/lib/jido/composer/orchestrator/llm_action.ex:145`).

[Risk: per-agent orchestrator module path requires non-trivial AST
work] → Pattern already established by ActionModule/SkillModule
emitters; same `Transformer.eval/3` mechanism.

[Risk: GenServer-per-session leaks if a turn crashes] → Use
`DynamicSupervisor` with `:transient` restart strategy and
short timeouts; the host can `Process.exit(pid, :shutdown)` to be
safe. Provide a `Harness.terminate/1` for explicit cleanup.

[Risk: cassettes drift when LLMs update their tokenization or model
versions change] → Cassettes are pinned to specific model strings;
re-recording requires the env var and a real API key, so it's an
explicit human action.

[Risk: dialyzer surfaces lots of new warnings] → Budget a half-day
for resolution; allow `.dialyzer_ignore.exs` entries only with a
written explanation.

## Migration Plan

This is a behavior-completion change, not an API change. Existing
callers of `Harness.new_session/2`, `run/3`, `resume/2`,
`trajectory/1`, `mutation_count/1` keep working.

**Behavior changes that downstream consumers see:**

1. `session.mutation_count` after `run/3` reflects actual mutations
   that happened during the turn (previously always 0 unless the host
   manually incremented).
2. `Harness.trajectory(session)` returns a populated list (previously
   only delegation entries appeared).
3. `Harness.resume/2` returns `{:ok, reply, session}` only after the
   agent actually finishes the turn (previously returned `{:ok, :resumed, session}`
   immediately and required the host to re-call `run/3`).
4. Repair-loop attempts are capped per (resource, action) within a
   turn; tools that fail validation repeatedly hit
   `:repair_exhausted` instead of looping forever.

These are all bug fixes from the spec's point of view, not API
breaks. The CHANGELOG documents each.

**Rollback:** revert the change; v0.1.0 behavior is preserved by
git history.

## Open Questions

1. **Should the SessionAgent persist across turns**, or be torn down
   and re-created at every `run/3`? Pro-persistence: trajectory
   accumulates naturally; cheaper. Pro-recreate: stateless turns; no
   leftover state. Default: persist for the session's lifetime, tear
   down on explicit `Harness.terminate/1` or supervisor shutdown.

2. **`max_turns` for the eval runner's `run/3` + `resume/2` loop** —
   reasonable default is the agent's `max_repair_loop_retries * 3`
   or a hard `12`; pick one in implementation.

3. **Cassette directory layout**: per-module or per-scenario? Per-
   scenario likely; the cassette name should be stable across runs.
   Default: `test/cassettes/<module-snake-case>/<scenario-snake-case>.json`.

4. **Should `req_cassette` be `:optional`?** It's used only in
   `dev/test`; pin to `~> 0.6`; not propagated to consumers.
