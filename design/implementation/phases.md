# Implementation Phases

Each phase ends with a working, testable artifact. Don't move on until
the previous phase is green.

## Phase 0 — Repo rename + dependencies (½ day)

- Rename the application: `ash_harness` (already correct).
- Update `mix.exs` with deps:
  ```elixir
  defp deps do
    [
      {:ash, "~> 3.0"},
      {:spark, "~> 2.0"},
      {:jido_composer, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:ash_postgres, "~> 2.0", optional: true},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
    ]
  end
  ```
- Replace `lib/ash_harness.ex` boilerplate with the package's
  top-level docs (link to README + design folder).
- Verify Jido docs at `https://hexdocs.pm/jido_composer` for the exact
  version pin.

**Artifact**: `mix deps.get && mix compile` succeeds.

## Phase 1 — Static introspection (no LLM, no runtime)

This is the foundation. Everything else builds on it.

| # | Module / area | Spec doc |
| --- | --- | --- |
| 1.1 | `AshHarness.Resource` extension + Info | `layers/01-resource-extension.md` |
| 1.2 | `AshHarness.Domain` extension + Info | `layers/02-domain-extension.md` |
| 1.3 | `AshHarness.Agent` DSL + Info | `layers/03-agent-dsl.md` |
| 1.4 | `AshHarness.Reachability` | `layers/04-reachability.md` |
| 1.5 | `AshHarness.Schema.Canonical` + ash_type_mapper | `layers/06-tool-generation.md` |
| 1.6 | `AshHarness.Schema.Render.{Anthropic,OpenAI,MCP}` | `layers/06-tool-generation.md` |
| 1.7 | Verifiers: scope, hints, traversable, hidden_attributes, delegates | `layers/03-agent-dsl.md` |
| 1.8 | Test resources (Ticket, Project, Comment, Member) | `implementation/test-strategy.md` |

**Artifacts**:

- A test agent compiles, full introspection works.
- `mix test test/ash_harness/{resource,domain,agent,reachability,schema}_test.exs` is green.
- `iex -S mix` lets you `AshHarness.Agent.Info.tool_list(MyAgent)` and
  see canonical schemas.

## Phase 2 — Context renderer

| # | Module / area | Spec doc |
| --- | --- | --- |
| 2.1 | `AshHarness.ContextRenderer` initial-text rendering | `layers/05-context-renderer.md` |
| 2.2 | Per-resource detail rendering (`render_resource/3`) | `layers/05-context-renderer.md` |
| 2.3 | Token-budget truncation | `layers/05-context-renderer.md` |
| 2.4 | Caching layer (per (agent, actor_id)) | `layers/05-context-renderer.md` |

**Artifact**: snapshot tests of rendered output against fixtures.

## Phase 3 — Tool generation

| # | Module / area | Spec doc |
| --- | --- | --- |
| 3.1 | `AshHarness.ToolGen.ActionModule` (compile-time emitter) | `layers/06-tool-generation.md` |
| 3.2 | `AshHarness.ToolGen.SkillModule` (per-resource Skill) | `layers/06-tool-generation.md` |
| 3.3 | `AshHarness.Tool.dynamic/2` (runtime API) | `layers/06-tool-generation.md` (ADR 0005) |
| 3.4 | BFCL-style schema unit tests | `benchmark/bfcl-schema-tests.md` |

**Artifact**: `MyAgent.Skills.Ticket` exists; tools have valid Anthropic
input schemas; round-trip from tool name + input to intent works.

## Phase 4 — Harness runtime

| # | Module / area | Spec doc |
| --- | --- | --- |
| 4.1 | Session, Intent, Result, TrajectoryEntry structs | `layers/07-harness-runtime.md` |
| 4.2 | Gate modules: scope, reasoning, budget | `layers/07-harness-runtime.md` |
| 4.3 | PolicyGate (Ash.can?) | `layers/07-harness-runtime.md` |
| 4.4 | ActionExecutor (read/create/update/destroy/run_action) | `layers/07-harness-runtime.md` |
| 4.5 | OrchestratorFactory: build a Jido orchestrator from an agent | `architecture/jido-integration.md` |
| 4.6 | `AshHarness.Harness.new_session/2`, `run/3`, `resume/2` | `layers/07-harness-runtime.md` |
| 4.7 | ConfirmationGate ↔ Jido ApprovalRequest plumbing | `layers/07-harness-runtime.md` |
| 4.8 | Repair loop formatter | `layers/08-repair-loop.md` |

**Artifact**: A test agent runs against test resources via
`AshHarness.Harness.run/3`; session trajectory captures all gate
outcomes; LLMStub-driven tests pass.

## Phase 5 — Delegation, telemetry

| # | Module / area | Spec doc |
| --- | --- | --- |
| 5.1 | `AshHarness.Delegation.initiate/4` | `layers/09-delegation.md` |
| 5.2 | Delegation depth limit + telemetry | `layers/09-delegation.md` |
| 5.3 | `AshHarness.Telemetry` event catalog | `layers/11-telemetry.md` |
| 5.4 | OTel attribute helpers | `layers/11-telemetry.md` |

**Artifact**: Two-agent delegation works end-to-end; telemetry events
fire; sample OTel trace shows AshHarness attributes on Jido spans.

## Phase 6 — Eval framework

| # | Module / area | Spec doc |
| --- | --- | --- |
| 6.1 | `AshHarness.Eval` DSL (`use AshHarness.Eval`, `scenario`, `gate`, `report`) | `layers/10-eval.md` |
| 6.2 | Scenario, Gate, Report structs | `layers/10-eval.md` |
| 6.3 | `AshHarness.Eval.Runner.run/2`, `run_all/2` | `layers/10-eval.md` |
| 6.4 | Trajectory checks (`includes_sequence`, `excludes`, `max_actions`, `max_tokens`) | `layers/10-eval.md` |
| 6.5 | Qualitative (judge model) | `layers/10-eval.md` |
| 6.6 | Test-only auto-confirm policy | `layers/10-eval.md` |

**Artifact**: A sample eval module with 3-5 scenarios runs; `mix
ash_harness.eval` reports per-scenario gate/report results.

## Phase 7 — τ-bench airline port

| # | Area | Spec doc |
| --- | --- | --- |
| 7.1 | New child package `ash_harness_tau_bench` | `benchmark/tau-bench-airline-port.md` |
| 7.2 | Resources: Customer, Reservation, Flight | `benchmark/tau-bench-airline-port.md` |
| 7.3 | Policies enforcing airline rules | `benchmark/tau-bench-airline-port.md` |
| 7.4 | Seeder from τ-bench JSON | `benchmark/tau-bench-airline-port.md` |
| 7.5 | Agent module (`TauBenchAirline.Agent`) | `benchmark/tau-bench-airline-port.md` |
| 7.6 | User simulator agent | `benchmark/tau-bench-airline-port.md` |
| 7.7 | 10 task scenarios | `benchmark/tau-bench-airline-port.md` |
| 7.8 | Multi-turn runner (custom eval extension) | `benchmark/tau-bench-airline-port.md` |
| 7.9 | Public results report (markdown) | `benchmark/tau-bench-airline-port.md` |

**Artifact**: Public README in the child package showing
gate-pass-rate over the implemented task subset; reproducible from
`mix tau_bench.run`.

## Phase 8 — Documentation, examples, polish

- `README.md` quickstart (≤5 minute path).
- Public docs at hexdocs (ExDoc).
- `examples/` directory:
  - `examples/triage/` — minimal agent on test resources.
  - `examples/postgres/` — same agent on AshPostgres.
  - `examples/multi_agent/` — supervisor + delegate.
- `docs/coming-from-langgraph-swarm.md` (already drafted in
  `architecture/`).
- `docs/coexistence-with-ash-ai.md`.
- `CHANGELOG.md` for v0.1.0.
- Hex publication.

## Time estimates (rough; assume one engineer)

| Phase | Estimated effort |
| --- | --- |
| 0 | ½ day |
| 1 | 5–7 days |
| 2 | 2–3 days |
| 3 | 3–4 days |
| 4 | 5–7 days |
| 5 | 2–3 days |
| 6 | 3–4 days |
| 7 | 5–8 days |
| 8 | 2–3 days |
| **Total** | **27–40 days** |

These are heavy estimates given the scope (a real benchmark port +
DSL + runtime + eval + observability). Pull what you can from
`jido_composer`'s built-ins to lower the runtime number.

## Critical path

Phase 0 → 1 → 3 → 4 → 6 → 7. Phases 2, 5, 8 are parallelizable with
the critical path once 1 is done.

## Out of v0.1.0 scope (deferred)

- Multi-model routing.
- Streaming responses through the harness.
- Cross-session persistent memory.
- An actual MCP server (renderer ships; router doesn't).
- Phoenix LiveView UI components.
- τ-bench retail port (v0.2).
- Full ~50-task τ-bench airline coverage (v0.2).
- Two-tier delegation (structured returns within trust zone) (v0.2).
- Pairwise qualitative scoring (v0.2).
