# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project state

v0.1.2 is the current stable release. Phases 1–6 of the implementation
plan have landed: resource/domain DSL extensions, agent DSL, reachability
graph, context renderer with progressive disclosure, canonical schema +
three renderers, compile-time `Jido.Action`/`Skill` generation, the full
gate pipeline (scope → reasoning → confirmation → budget → policy),
repair loop, cross-agent delegation (now LLM-invokable via a wired skill),
telemetry with OTel attribute attachment, and the eval framework. The
codebase is ~90 modules under `lib/ash_harness/` plus ~95 test files; the
τ-bench airline port lives at `benchmarks/tau_bench_airline/`. The
`design/` folder is **reference documentation**, not a future-state spec —
treat it as authoritative for *intent* and `lib/`/`test/` as authoritative
for *what is actually shipped*. Where the two disagree, the audit-followup
change (`openspec/changes/audit-followup-v0-1-2/`) records which side won
and why.

Quick-jump table to the most-touched code locations:

| Concern | Code |
| --- | --- |
| Runtime entry point | `lib/ash_harness/harness.ex` (`new_session/2`, `run/3`, `resume/2`) |
| Dispatch + gates | `lib/ash_harness/harness/generated_action.ex` |
| Structured errors | `lib/ash_harness/errors/` (seven `defexception` structs) |
| Session state | `lib/ash_harness/harness/session_agent.ex` (supervised GenServer) |
| Compile-time tools | `lib/ash_harness/tool_gen/` (action + skill + orchestrator modules) |
| Delegation skill | `lib/ash_harness/delegation/skill.ex` (Jido.Action) |
| Telemetry | `lib/ash_harness/telemetry.ex` + every `*_gate.ex` |
| Eval runner | `lib/ash_harness/eval/runner.ex` |

The original `AshAgent` spec the user pasted into the first conversation
is **superseded** by the design folder; deviations from that spec
(renames, scope changes, runtime choice) are documented in `design/adrs/`.

## What AshHarness is

An Elixir library that turns Ash Framework resources/domains into the
operating layer for AI agents driven by `jido_composer`. The agent's
understanding of what it can do is derived from the same Ash resource
definitions and policies that enforce what it can do — one source of
truth.

The mix package is `ash_harness`; everything lives under `AshHarness.*`.

## Architecture you have to know before editing

Three things together explain the whole design. Skim these in order:

1. **`design/architecture/system-context.md`** — the boundaries.
   AshHarness owns: resource/domain DSL extensions, agent DSL, reachability
   graph, context renderer, canonical schema, compile-time tool generation,
   the gate pipeline (scope/reasoning/budget/policy), repair loop,
   delegation, eval framework. AshHarness does **not** own: the LLM loop,
   provider transport, HITL plumbing, checkpointing, OTel spans — those
   come from `jido_composer`. AshHarness does **not** modify Ash behavior;
   resource/domain extensions are introspectable metadata only.

2. **`design/architecture/jido-integration.md`** — the runtime contract.
   For each agent, AshHarness generates one `Jido.Action` module per
   scoped action and one `Jido.Composer.Skill` per resource. The
   generated `Jido.Action.run/2` invokes `AshHarness.Harness.GeneratedAction.dispatch/5`,
   which runs all gates before calling Ash. Authorization is enforced
   here, *not* delegated to Jido. Confirmations halt with
   `Jido.Composer.HITL.ApprovalRequest`; resume re-enters the gate
   pipeline after the budget gate.

3. **`design/architecture/data-flow.md`** — the request lifecycle.
   Compile-time: DSL → transformers persist reachability + tool list →
   verifiers validate → ToolGen emits sibling modules. Runtime: host app
   builds session → orchestrator assembles with rendered context +
   skills + DynamicAgentNode → LLM emits tool_use → generated Action's
   gates run → Ash executes → trajectory + telemetry → loop.

The 11 layer docs in `design/layers/` map 1:1 to the module tree in
`design/architecture/module-tree.md`. When asked to implement layer N,
that doc is the spec.

## Decisions that will trip you up if you don't know them

These are recorded in ADRs (`design/adrs/`); the highlights:

- **Runtime is `jido_composer`, not a custom loop** (ADR 0001). Don't add
  `AshHarness.LLM.Adapter` or rebuild orchestration — that abstraction
  was rejected.
- **Eval scoring is pass/fail gates + diagnostic reports**, not weighted
  averages (ADR 0002). DSL uses `gate :resource_state` and
  `report :trajectory` / `report :qualitative`. There is no
  `composite_score`.
- **Ralph Loop is renamed to Repair Loop** (ADR 0003). Module is
  `AshHarness.Harness.Repair`; constraint is `max_repair_loop_retries`.
- **Delegation returns text only** (ADR 0004) — no structured returns,
  no shared conversation history. Each agent uses its own scope; A never
  sees B's records.
- **Tool generation is hybrid** (ADR 0005): compile-time `Skill` +
  per-action `Jido.Action` modules **plus** runtime
  `AshHarness.Tool.dynamic/2`. Both flow through the same gate pipeline.
- **One canonical schema, three renderers** (ADR 0006): Anthropic,
  OpenAI, MCP. Don't render to provider formats directly.
- **Progressive disclosure is in v0.1.0** via per-resource `Skill`s +
  `DynamicAgentNode` (ADR 0007). Initial context renders resource
  *summaries* only; details load on demand via `load_resource_skill`.
- **Library is data-layer-agnostic; ETS is the default** for tests and
  examples (ADR 0008). `ash_postgres` is `optional: true`.
- **`mutation_count` is per-turn, novel to AshHarness** (ADR 0009). Reads
  don't count; failed mutations don't count; "turn" = one
  `run/2`/`resume/2` call.
- **Position vs `ash_ai` is "alternative with different opinions"**
  (ADR 0010). Don't fold AshHarness into ash_ai; co-existence is fine.

## Spark DSL conventions to respect

When implementing extensions (`AshHarness.Resource`, `AshHarness.Domain`,
`AshHarness.Agent`):

- Use `Spark.InfoGenerator` for the `Info` modules. Don't roll introspection
  by hand.
- **Transformers persist derived data; verifiers do all validation.** This
  is a project rule (interview decision). A verifier reading transformer
  output is the standard pattern; reversing this leads to ordering bugs.
- Transformers must declare `after?(Ash.Resource.Transformers.SetPrimaryActions)`
  when reading action metadata.
- Use `Spark.Dsl.Transformer.persist/3` for derived state the Info module
  exposes.

## Build, test, lint commands

The dependency list in `design/implementation/phases.md` (Phase 0) shows
what `mix.exs` should become; the current `mix.exs` is empty scaffold.

Once deps are wired:

```
mix deps.get
mix compile
mix test                         # default — ETS only
mix test path/to/file_test.exs   # one file
mix test path/to/file_test.exs:42 # one test by line
mix format                       # uses .formatter.exs (already present)
mix format --check-formatted     # CI check
```

Phase-8 CI plan (per `design/implementation/test-strategy.md`) adds:

```
MIX_ENV=postgres mix test       # postgres-tagged tests (Docker required)
MIX_ENV=integration mix test    # real LLM; nightly only, requires API key
mix credo --strict
mix dialyzer
```

For LLM-mocked tests use `Jido.Composer.LLMStub`; integration tests are
gated with `@tag :integration`.

## Where to start when given a task

| Task type | Start here |
| --- | --- |
| "implement layer N" | `design/layers/0N-*.md`, then the linked ADRs |
| "design a new feature" | check `design/implementation/open-questions.md` first; the question may already be tracked |
| "explain the architecture" | `design/overview.md` → `design/architecture/system-context.md` |
| "what about ash_ai / jido_composer / langgraph?" | `design/architecture/coming-from-langgraph-swarm.md`, ADR 0001, ADR 0010 |
| "rename / change a public name" | `design/glossary.md` records the canonical vocabulary; update there too |
| "what's the public API?" | `design/implementation/public-api.md` |

## House rules from the design phase

- The user uses `jido_composer` (their own library, hex 0.5.x). When
  designing or implementing, prefer Jido primitives over rolling our own.
- Web research tools were denied during the design interview; design docs
  flag training-time claims that need verification before publishing
  (see `design/implementation/open-questions.md`, items #1–#3).
- The original `AshAgent` spec the user pasted is **superseded**. Renames:
  `AshAgent` → `AshHarness`; `Ralph Loop` → `Repair Loop`;
  `assert_resource` → `gate :resource_state`; `assert_trajectory` →
  `report :trajectory`. If you see the old names in code or future user
  messages, treat them as a hint to check `design/glossary.md`.

## Commit policy

- **No `Co-Authored-By:` trailer.** Commits must not include the
  `Co-Authored-By: Claude ... <noreply@anthropic.com>` line that
  Claude Code adds by default. When committing on this repo, omit the
  trailer. If a commit slips through with it, follow up with
  `git filter-repo --message-callback` to strip it.
