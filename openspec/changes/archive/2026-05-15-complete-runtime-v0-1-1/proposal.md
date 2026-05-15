# Proposal — Complete the Runtime (v0.1.1)

## Why

v0.1.0 shipped the structural scaffold for AshHarness: DSL extensions,
compile-time tool generation, the canonical schema and renderers, the
context renderer, the gate pipeline mechanics, telemetry events, and an
eval-framework macro surface. 143 unit tests pass against that surface
and the τ-bench airline child package compiles.

What it doesn't yet do is **run an actual agent against an actual LLM
end-to-end and measure it**. Several runtime pieces were shipped as
stubs:

- Budget counter doesn't bump after a successful mutation.
- Trajectory entries are never appended during dispatch.
- Repair-attempt counter is never incremented; `:repair, :exhausted`
  never fires.
- `Harness.resume/2` records the approval but doesn't hand it back to
  Jido's suspension machinery — the host has to re-call `run/3`, which
  re-rolls the LLM turn.
- `Eval.Runner.run/2` evaluates gates against an empty context; it
  never actually drives the agent through the scenario's prompt.
- Eval scenarios share ETS state.
- τ-bench scenarios use `gate :invariant do true end` placeholders; no
  scenario actually exercises tool calls.
- `mix credo --strict` and `mix dialyzer` have never run.

v0.1.1 closes the runtime gaps so the library can be used to build,
run, and evaluate agents end-to-end.

## What Changes

- Replace the static `%Session{}` field with a supervised
  `AshHarness.Harness.SessionAgent` GenServer. The session struct
  becomes a snapshot at turn boundaries; the GenServer owns mutable
  per-turn state (mutation_count, trajectory, repair_attempts,
  approvals) and `GeneratedAction.dispatch/5` reads/updates through
  the pid carried in `ctx[:ash_harness_session_pid]`.
- Bump `mutation_count` after a successful mutating action.
- Append a `%TrajectoryEntry{}` for every gate outcome and every
  executed action.
- Track per-(resource, action) repair attempts; refuse with a
  retry-limit message and emit `[:ash_harness, :repair, :exhausted]`
  when the cap is hit.
- Spike Jido's suspension/resume API; rewrite `Harness.resume/2` to
  hand the `%ApprovalResponse{}` back to the orchestrator at the
  suspension point instead of relying on the host to re-call `run/3`.
- Configure `confirm_before` tool nodes with `requires_approval: true`
  so the orchestrator strategy halts at the right moment. Likely
  requires generating a per-agent `use Jido.Composer.Orchestrator`
  module via `EmitTools` instead of `Skill.assemble/2`, since the
  latter doesn't accept node-level options.
- Add per-scenario isolation in `Eval.Runner.run/2`: ETS delete-all
  for ETS-backed resources; AshPostgres sandbox checkout + rollback
  when applicable.
- Rewrite `Eval.Runner.run/2` to actually drive the agent: open
  sandbox → run setup → `Harness.new_session` → `Harness.run` (with
  auto-confirm loop) → evaluate gates and reports against the
  resulting trajectory and final resource state.
- Add `req_cassette` as a test/dev dep; wire its Req plug into the
  agent's `req_options` so eval runs in default `mix test` replay
  pre-recorded LLM responses.
- Implement the `:auto_confirm` modes (`:always_approve`,
  `:always_reject`, `{:custom, fn intent -> :approved | :rejected end}`).
- Re-script 3–5 τ-bench scenarios to drive the agent for real via
  cassettes (`change_flight`, `cancel`, basic-fare policy denial,
  optionally cross-customer denial and search). Mark the remaining
  scenarios as v0.2 placeholders.
- Run `mix credo --strict` and `mix dialyzer` for the first time;
  resolve flagged issues (or document explicit ignores).
- Update `CHANGELOG.md` and bump version to `0.1.1`.

## Capabilities

### Modified Capabilities

- `harness-runtime`: session is now backed by a supervised GenServer;
  mutation counter, trajectory, repair counter, and approvals all
  mutate during a turn rather than only at turn boundaries.
  Confirmation resume hands the `ApprovalResponse` straight into the
  Jido suspension machinery instead of relying on host replay.
- `repair-loop`: per-(resource, action) attempt cap is enforced;
  `[:ash_harness, :repair, :exhausted]` fires when reached; repair
  feedback messages distinguish "retryable, attempt N/M" from
  "limit reached, try another approach".
- `eval-framework`: scenarios drive a real agent via
  `Harness.new_session` + `Harness.run`; isolation per scenario (ETS
  delete-all or AshPostgres rollback); `req_cassette` plug for
  deterministic LLM replay; `:auto_confirm` modes wired through
  `Harness.resume`.
- `tau-bench-airline-port`: at least 3 scenarios drive the agent end-
  to-end via committed cassettes; gate-pass-rate against the headline
  model is reported in the README.

### Added Capabilities

None — this change completes existing capabilities rather than
introducing new ones.

## Impact

- **Code**: new `lib/ash_harness/harness/session_agent.ex` and
  `session_supervisor.ex`; rewrites of `harness.ex`,
  `generated_action.ex`, `orchestrator_factory.ex`, `eval/runner.ex`;
  edits to gates and dispatch to append trajectory entries; possibly
  a new emitter under `tool_gen/orchestrator_module.ex` for the
  per-agent orchestrator module path.
- **Mix package**: adds `{:req_cassette, "~> 0.6", only: [:dev, :test]}`.
  Optional supervisor started under the application tree.
- **Public API**: `Harness.new_session/2`, `run/3`, `resume/2`,
  `trajectory/1`, `mutation_count/1` keep their existing signatures.
  Session struct gains/loses no fields that callers consume. The
  semantics tighten — values returned reflect actual per-turn state.
- **Telemetry**: `[:ash_harness, :repair, :exhausted]` starts firing;
  existing events unchanged.
- **CI**: `mix credo --strict` and `mix dialyzer` join the matrix.
  Cassettes live under `test/cassettes/` and
  `benchmarks/tau_bench_airline/test/cassettes/` (committed); CI
  replays only.
- **Documentation**: README quickstart updated with the
  `req_cassette` step for tests. `benchmarks/tau_bench_airline/README.md`
  reports a real gate-pass-rate with the headline model.
- **Out of v0.1.1**: progressive disclosure via `DynamicAgentNode`
  (ADR 0007, still v0.2); `ash_ai` positioning verification (open
  question #1, pre-publication step); upstream τ-bench schema
  verification (open question #3); two-tier delegation.
