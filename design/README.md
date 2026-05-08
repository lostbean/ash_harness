# AshHarness — Design Documentation

**Version:** 0.1.0-design
**Status:** Draft (interview-driven)
**Last Updated:** 2026-05-08

This folder contains the design documentation for **AshHarness**, an Elixir
library that turns Ash Framework resources and domains into the operating
layer for AI agents driven by `jido_composer`.

## How to read this

If you have 10 minutes, read in order:

1. [`overview.md`](overview.md) — what AshHarness is, who it's for, and what
   it doesn't do.
2. [`architecture/system-context.md`](architecture/system-context.md) — where
   AshHarness sits between Ash, Jido Composer, and the LLM.
3. [`architecture/module-tree.md`](architecture/module-tree.md) — the public
   module layout and what each module owns.
4. [`implementation/phases.md`](implementation/phases.md) — what we ship
   in v0.1.0 and the order we build it in.

If you're an AI/agent engineer new to Ash, also read:
[`architecture/coming-from-langgraph-swarm.md`](architecture/coming-from-langgraph-swarm.md).

## Folder layout

```
design/
├── README.md                          # this file
├── overview.md                        # what & why
├── glossary.md                        # vocabulary
├── architecture/
│   ├── system-context.md              # external boundaries
│   ├── module-tree.md                 # internal layout
│   ├── data-flow.md                   # request lifecycle
│   ├── jido-integration.md            # the Jido boundary
│   └── coming-from-langgraph-swarm.md # onboarding for non-Ash devs
├── layers/
│   ├── 01-resource-extension.md       # AshHarness.Resource DSL
│   ├── 02-domain-extension.md         # AshHarness.Domain DSL
│   ├── 03-agent-dsl.md                # AshHarness.Agent DSL (`use AshHarness.Agent`)
│   ├── 04-reachability.md             # graph derivation
│   ├── 05-context-renderer.md         # prompt composition + progressive disclosure
│   ├── 06-tool-generation.md          # canonical schema + Skill/Action emission
│   ├── 07-harness-runtime.md          # execution mediation, scope+policy gates
│   ├── 08-repair-loop.md              # validation-failure repair
│   ├── 09-delegation.md               # cross-agent boundaries
│   ├── 10-eval.md                     # gate + diagnostics framework
│   └── 11-telemetry.md                # OTel + AshHarness events
├── adrs/
│   ├── 0001-jido-composer-as-runtime.md
│   ├── 0002-eval-gate-vs-weighted-average.md
│   ├── 0003-rename-ralph-loop-to-repair.md
│   ├── 0004-delegate-text-only-anti-corruption.md
│   ├── 0005-tool-generation-hybrid.md
│   ├── 0006-canonical-schema-multi-renderer.md
│   ├── 0007-progressive-disclosure-via-dynamic-skills.md
│   ├── 0008-data-layer-agnostic.md
│   ├── 0009-mutation-budget-per-turn.md
│   └── 0010-position-vs-ash-ai.md
├── benchmark/
│   ├── tau-bench-airline-port.md
│   └── bfcl-schema-tests.md
└── implementation/
    ├── phases.md                      # ordered phases
    ├── test-strategy.md
    ├── public-api.md                  # function-level surface
    └── open-questions.md              # what we still need to answer
```

## Decisions captured (from the design interview)

| Decision | Choice |
| --- | --- |
| Library name | **AshHarness** is the umbrella; everything sits under `AshHarness.*`. The mix package is `ash_harness`. |
| Audience for v0.1.0 | AI/agent engineers from other ecosystems (LangGraph/Swarm-fluent, Elixir/Ash novices). |
| v0.1.0 success | End-to-end demo agent + a port of the **τ-bench airline domain** as a credible third-party benchmark. |
| Spec authority | Hybrid — research conflicts surface to the user; ADRs record the call. |
| Position vs `ash_ai` | Build alongside as alternative with different opinions (scope-as-DSL, eval-first, agent-as-first-class). |
| LLM transport | **`jido_composer`** is the runtime; AshHarness is its Ash plumbing. |
| Tool schema | Single canonical JSON Schema; renderers project to Anthropic, OpenAI, MCP. |
| Progressive disclosure | In v0.1.0; via `DynamicAgentNode` + per-resource `Skill`s. |
| Eval scoring | Deterministic = pass/fail gate; trajectory + qualitative reported as diagnostics. |
| Headline benchmark | τ-bench **airline** domain ported into Ash. |
| Delegation scope | Delegate uses its own scope (anti-corruption); returns text-only. |
| Data layer | Both supported; ETS default, AshPostgres optional. |
| Tool generation | Hybrid: compile-time `Skill` + per-action `Jido.Action` modules **plus** runtime dynamic tool API. |
| Telemetry | Forward Jido OTel spans; emit AshHarness child events for scope/policy/eval. |
| Eval DSL | `gate` for pass/fail, `report` for diagnostics. |
| Validation | Transformers persist derived data; verifiers do all validation. |
| Renamed | `Ralph Loop` → **Repair Loop** (`AshHarness.Harness.Repair`). |

See [`adrs/`](adrs/) for the full reasoning behind each.
