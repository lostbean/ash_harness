# Proposal — Bootstrap AshHarness v0.1.0

## Why

The repository ships a 35-file design folder describing AshHarness — a
library that turns Ash Framework resources into the operating layer for AI
agents driven by `jido_composer` — but `lib/` and `test/` contain only
placeholder code. The design is settled (16+ interview-locked decisions,
10 ADRs); v0.1.0 needs to translate it into running code, including a
τ-bench airline-domain port that gives the library credible third-party
benchmark validation. Ship the design now to unblock downstream work
(eval harness, multi-agent demos, hex publication).

## What Changes

- Wire production deps in `mix.exs`: `ash ~> 3.0`, `spark ~> 2.0`,
  `jido_composer ~> 0.5`, `jason`, `telemetry`; `ash_postgres` optional.
- Add the `AshHarness.Resource` Spark DSL extension (resource-level
  agent annotations: description, hints, traversable, hidden_attributes)
  with Spark-generated Info module and verifier.
- Add the `AshHarness.Domain` Spark DSL extension (domain description
  and ubiquitous-language terms) with Info and verifier.
- Add the `AshHarness.Agent` DSL (`use AshHarness.Agent`) with sections
  `identity`, `scope`, `behavior`, `delegates_to`, `constraints`, plus
  transformers (reachability, tool list) and seven verifiers.
- Add reachability graph computation (`AshHarness.Reachability`)
  consuming scope + traversable annotations.
- Add the canonical schema artifact (`AshHarness.Schema.Canonical`) and
  three pure renderers (Anthropic, OpenAI, MCP); Ash-type → JSON-Schema
  mapper.
- Add the context renderer (`AshHarness.ContextRenderer`) producing
  initial-text + per-resource-detail strings, with token-budget
  truncation and per-(agent, actor) caching.
- Add compile-time tool generation (`AshHarness.ToolGen`) that emits one
  `Jido.Action` module per scoped action and one `Jido.Composer.Skill`
  per scoped resource, plus the runtime `AshHarness.Tool.dynamic/2` API
  for session-scoped tools.
- Add the harness runtime (`AshHarness.Harness`): session struct,
  intent struct, result struct, trajectory entry; gates for scope,
  reasoning, confirmation (bridges to Jido `ApprovalRequest`), budget,
  and policy (`Ash.can?`); action executor dispatching to
  `Ash.read/create/update/destroy/run_action`; orchestrator factory
  that assembles a Jido orchestrator with a `DynamicAgentNode` for
  progressive disclosure.
- Add the repair loop (`AshHarness.Harness.Repair`) — formerly "Ralph
  Loop" — that formats Ash validation errors for re-injection into the
  LLM context.
- Add cross-agent delegation (`AshHarness.Delegation`) with text-only
  return, depth limit, and anti-corruption boundary (delegate uses its
  own scope, A never sees B's records).
- Add the telemetry catalog (`AshHarness.Telemetry`) emitting
  `[:ash_harness, …]` events and attaching `ash_harness.*` attributes
  to active Jido OTel spans.
- Add the eval framework (`AshHarness.Eval`): `gate :resource_state` /
  `gate :invariant` (pass/fail) and `report :trajectory` /
  `report :qualitative` (diagnostic) — no composite weighted score.
- Add the τ-bench airline-domain port as a child package
  (`benchmarks/tau_bench_airline/`): Customer, Reservation, Flight
  resources with policies; agent module; user-simulator agent; ~10
  scenario tasks.
- Add test resources, agents, and the BFCL-style schema unit tests.
- Add ExDoc, CHANGELOG, examples (`examples/triage`, `examples/postgres`,
  `examples/multi_agent`), and a "Coming from LangGraph/Swarm" guide.

## Capabilities

### New Capabilities

- `resource-annotations`: agent-facing metadata (`description`, `hint`,
  `traversable`, `hidden_attributes`) on Ash resources via the
  `AshHarness.Resource` extension; introspection and compile-time
  validation.
- `domain-annotations`: domain-level vocabulary (`description`,
  `term`) via the `AshHarness.Domain` extension.
- `agent-dsl`: top-level agent declaration (`use AshHarness.Agent`)
  covering identity, scope, behavior, delegation, constraints; agent
  module compile-time validation.
- `reachability-graph`: derived graph of resources × allowed
  relationships, given an agent's scope and resource annotations.
- `tool-schema`: canonical JSON-Schema artifact per scoped action +
  Anthropic / OpenAI / MCP renderers.
- `tool-generation`: compile-time emission of `Jido.Action` modules and
  per-resource `Jido.Composer.Skill`s; plus runtime
  `AshHarness.Tool.dynamic/2` for session-scoped tools.
- `context-rendering`: agent system-prompt generation with progressive
  disclosure (resource summaries up front, full detail on demand).
- `harness-runtime`: session lifecycle, gate pipeline (scope,
  reasoning, confirmation, budget, policy), action dispatch,
  trajectory, integration with `jido_composer`'s orchestrator.
- `repair-loop`: validation-error formatting for LLM re-injection;
  retryable-error classification; per-action repair-attempt cap.
- `delegation`: cross-agent text-only return with anti-corruption
  boundary, depth limit, separate scopes per agent.
- `eval-framework`: scenario DSL with `gate` (pass/fail) and `report`
  (diagnostic) blocks; runner with isolation, judge-model integration,
  and trajectory checks.
- `telemetry-events`: AshHarness-specific `:telemetry` events and
  OTel attribute attachment on Jido spans.
- `tau-bench-airline-port`: a child-package τ-bench airline-domain
  benchmark (resources, agent, user simulator, scenarios) used as the
  v0.1.0 headline benchmark.

### Modified Capabilities

None — the `openspec/specs/` directory is empty; this is a greenfield
v0.1.0 bootstrap.

## Impact

- **Code**: replaces the placeholder `lib/ash_harness.ex` with the full
  module tree from `design/architecture/module-tree.md`. New
  `lib/ash_harness/**` and `test/support/**`.
- **Mix package**: production deps added; `ash_postgres` optional for
  `MIX_ENV=postgres mix test`.
- **Public API**: defined by `design/implementation/public-api.md` —
  introspection, harness, delegation, repair, eval. Stable for v0.1.x.
- **Telemetry surface**: new `[:ash_harness, …]` events; consumers must
  attach handlers (catalog in `design/layers/11-telemetry.md`).
- **Documentation**: `README.md` rewritten; ExDoc on hex; new examples
  directory.
- **CI**: matrix expands to default (ETS), `MIX_ENV=postgres`,
  `MIX_ENV=integration` (real LLM, nightly), plus `mix credo --strict`
  and `mix dialyzer`.
- **Downstream**: enables hex publication of `ash_harness` and the
  separate `ash_harness_tau_bench` benchmark package.
- **Out of v0.1.0**: streaming, multi-model routing, persistent memory,
  Phoenix LiveView components, full ~50-task τ-bench coverage, MCP
  server router, two-tier delegation. Tracked in
  `design/implementation/open-questions.md` and the v0.2 backlog.
