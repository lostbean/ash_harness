# AshHarness — Overview

## 1. What it is

AshHarness is an Elixir library that lets you take an existing Ash Framework
application and operate it through AI agents. It provides:

- A **DSL** (`use AshHarness.Agent`) for declaring an agent's identity,
  scope, behavior, delegation graph, and operational constraints.
- **Resource and domain extensions** (`AshHarness.Resource`,
  `AshHarness.Domain`) for annotating Ash resources with agent-facing
  metadata: descriptions, action hints, traversable relationships, hidden
  attributes, ubiquitous-language terms.
- A **context renderer** that introspects the resource graph and produces
  the agent's system prompt — including a navigational map derived from
  reachability, with progressive disclosure of resource detail on demand.
- **Compile-time tool generation**: each scoped action becomes a
  `Jido.Action` module, packaged into a per-resource `Jido.Composer.Skill`,
  with a canonical JSON-Schema artifact that renders to Anthropic, OpenAI,
  and MCP formats.
- A **harness runtime** that wraps `jido_composer`'s orchestrator: enforces
  scope at tool-exposure time, runs `Ash.can?` at execution time, applies
  per-turn mutation budgets, mediates confirmation flows, and emits
  telemetry alongside Jido's OpenTelemetry spans.
- A **repair loop** that re-feeds Ash validation errors to the model so it
  can correct its input.
- **Cross-agent delegation** with an anti-corruption boundary: delegates
  receive their own scope and return text only.
- An **evaluation framework** with a deterministic-as-gate model:
  resource-state assertions are pass/fail, trajectory and qualitative
  metrics are reported as diagnostics for regression detection.

## 2. Why

The thing that makes Ash compelling as a foundation for AI agents is the
same thing that makes Ash compelling for traditional applications:
**the resource definitions are the source of truth.** When you write
`update :assign do … end`, that declaration powers your API, your
authorization, your validations, your audit logs — and, with AshHarness,
also your agent's tool description and JSON schema.

The core invariant of AshHarness: **what the agent thinks it can do is
derived from what the actor is actually allowed to do.** The same Ash
policy that protects your REST endpoint protects your agent's tool call.
There is one source of truth.

## 3. Why this is different from `ash_ai`

The Ash ecosystem already has [`ash_ai`](https://github.com/ash-project/ash_ai)
which exposes Ash actions to LLMs and ships an MCP server. AshHarness
intentionally takes a different position:

- **Agent as a first-class entity.** `ash_ai` exposes actions as tools.
  AshHarness models the agent itself — identity, scope, behavior, delegation
  graph, constraints — as a top-level declaration. You don't bolt agents
  onto a domain; you declare them.
- **Eval-first.** AshHarness ships a three-layer evaluation framework
  (gate + diagnostics) as a peer of the runtime, not an afterthought.
- **Explicit scope as DSL.** `ash_ai` filters via Ash policies; AshHarness
  declares scope statically in the agent module *as well as* enforcing
  policies at execution. Two-layer auth — the agent literally cannot see
  tools outside its scope.
- **Built on `jido_composer`.** Rather than a custom inference loop,
  AshHarness leverages a production-grade composer with HITL, checkpointing,
  OTel observability, and skill assembly already in place.

These libraries can co-exist. ADR
[`0010-position-vs-ash-ai.md`](adrs/0010-position-vs-ash-ai.md) records the
reasoning.

## 4. Audience

v0.1.0 is optimized for **AI/agent engineers coming from other ecosystems**
(LangGraph, Swarm, OpenAI Agents SDK, smolagents) who are willing to learn
just enough Ash to use it.

This shapes:

- A "Coming from LangGraph/Swarm" guide that maps familiar concepts to Ash.
- DSL examples favor the agent-engineer mental model — explicit identity,
  scope, behavior — over Ash idioms.
- The headline demo is a port of **τ-bench airline domain**, a benchmark
  this audience already knows by reputation.

## 5. v0.1.0 scope

**In:**

- `AshHarness.Resource` and `AshHarness.Domain` DSL extensions.
- `AshHarness.Agent` DSL (`use AshHarness.Agent`).
- Reachability graph computation.
- Context renderer with **progressive disclosure** (per-resource
  `Skill`s loaded by `DynamicAgentNode`).
- Compile-time tool generation: per-resource `Skill`s with per-action
  `Jido.Action` modules, plus a runtime `AshHarness.Tool.dynamic/2` API
  for session-scoped tools.
- Harness runtime wrapping `jido_composer` orchestrators with scope,
  `Ash.can?`, mutation budgets, confirmation flows.
- Repair loop (formerly Ralph Loop) for validation-failure feedback.
- Cross-agent delegation with text-only anti-corruption boundary.
- Eval framework: `gate` (pass/fail) + `report` (diagnostics).
- Telemetry: AshHarness child events on Jido OTel spans.
- Test resources (Ticket / Project / Comment / Member) for the test suite.
- **τ-bench airline domain port** as the headline benchmark.

**Out:**

- Multi-model routing (different actions to different LLMs).
- Meta-harness self-improvement.
- Cross-session persistent memory.
- Streaming partial responses through the harness.
- Phoenix LiveView UI components.
- State machine declarations (use Ash validations / `ash_state_machine`).

## 6. The 30-second mental model

```text
                       ┌─────────────────────────────────┐
                       │         your application        │
                       │                                 │
                       │   use AshHarness.Agent          │
                       │     identity / scope /          │
                       │     behavior / delegates_to     │
                       └────────────┬────────────────────┘
                                    │ compile time
                                    ▼
   ┌────────────────────────────────────────────────────────────┐
   │                       AshHarness                           │
   │                                                            │
   │   Resource extensions       Agent DSL & verifiers          │
   │       │                           │                        │
   │       ▼                           ▼                        │
   │   ContextRenderer          ToolGenerator                   │
   │   (system prompt)          (Skills + Actions)              │
   │       └─────────────┬─────────────┘                        │
   │                     ▼                                      │
   │              Harness wrapper                               │
   │   (scope gate · Ash.can? · mutation budget · repair)       │
   └─────────────────────┬──────────────────────────────────────┘
                         ▼
                  Jido.Composer.Orchestrator
                  (LLM loop · HITL · checkpoint · OTel)
                         │
                         ▼
                       Anthropic / OpenAI / MCP
```

The agent author writes `use AshHarness.Agent`. AshHarness derives
context, schema, tools, and policy gates from existing Ash resources.
`jido_composer` runs the inference loop. The agent acts on the resources
via Ash actions, with one source of truth for "what's allowed."
