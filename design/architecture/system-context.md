# Architecture — System Context

This document shows where AshHarness sits in the larger system and what
it does *not* own.

## External actors

```text
                                     ┌──────────────────────┐
                                     │       human user     │
                                     └──────────┬───────────┘
                                                │ messages, approvals
                                                ▼
       ┌──────────────────────────────────────────────────────────────────┐
       │                      your application                            │
       │            (Phoenix / LiveView / GenServer / CLI)                │
       └──────────────────────────────────────────────────────────────────┘
                  │                          │                       │
        defines agents          calls runtime              receives traces
                  │                          │                       │
                  ▼                          ▼                       ▼
       ┌────────────────────┐    ┌─────────────────────┐   ┌──────────────────┐
       │  user's Ash app    │    │    AshHarness       │   │   OpenTelemetry  │
       │  (resources,       │◄──►│   (this library)    │──►│   collector      │
       │   domains,         │    │                     │   │                  │
       │   policies)        │    └──────────┬──────────┘   └──────────────────┘
       └────────────────────┘               │
              ▲                              │ wraps
              │ Ash.* calls                  │
              │ (with actor)                 ▼
              │                  ┌─────────────────────┐
              └──────────────────┤  jido_composer      │
                                 │  Orchestrator       │
                                 │  (LLM loop, HITL,   │
                                 │   checkpoint, OTel) │
                                 └──────────┬──────────┘
                                            │ tool calls
                                            ▼
                                 ┌─────────────────────┐
                                 │  LLM provider       │
                                 │  (Anthropic /       │
                                 │   OpenAI / MCP)     │
                                 └─────────────────────┘
```

## What AshHarness owns

| Concern | Owner |
| --- | --- |
| Annotating Ash resources/domains for agents | **AshHarness** (`Resource`, `Domain` extensions) |
| Declaring agent identity, scope, behavior, delegation, constraints | **AshHarness** (`Agent` DSL) |
| Computing the reachability graph from scope + `traversable` | **AshHarness** (`Reachability`) |
| Rendering the agent's system prompt from the resource graph | **AshHarness** (`ContextRenderer`) |
| Generating per-action `Jido.Action` modules and per-resource `Skill`s | **AshHarness** (`ToolGen`) |
| Producing the canonical JSON Schema and projecting to provider formats | **AshHarness** (`Schema`) |
| Enforcing scope before exposing tools to the orchestrator | **AshHarness** (`Harness`) |
| Calling `Ash.can?` and `Ash.run_action` with the agent's actor | **AshHarness** (`Harness`) |
| Mutation budget per turn, reasoning requirement, confirmation flow | **AshHarness** (`Harness`) |
| Repair loop: format Ash validation errors back to the LLM | **AshHarness** (`Repair`) |
| Cross-agent delegation with text-only return | **AshHarness** (`Delegation`) |
| Three-layer evaluation (gate + diagnostics) | **AshHarness** (`Eval`) |
| AshHarness-specific telemetry events and OTel attributes | **AshHarness** (`Telemetry`) |

## What `jido_composer` owns

| Concern | Owner |
| --- | --- |
| The LLM inference loop (model call → tool call → repeat) | **`jido_composer`** (`Orchestrator`) |
| Provider transport (Anthropic, OpenAI, etc., via Jido AI underneath) | **`jido_composer`** |
| HITL approval requests/responses | **`jido_composer`** (`HumanNode`, `ApprovalRequest`/`ApprovalResponse`) |
| Checkpoint/resume, durable persistence | **`jido_composer`** (`Checkpoint`) |
| OpenTelemetry spans for orchestrator/tool/LLM | **`jido_composer`** |
| Skill assembly, dynamic agent nodes | **`jido_composer`** (`Skill`, `DynamicAgentNode`) |
| Workflow FSMs, fan-out, map nodes | **`jido_composer`** (out of AshHarness's primary scope but available) |

## What Ash owns

| Concern | Owner |
| --- | --- |
| Resource definition (attributes, relationships, actions, validations) | **Ash** |
| Authorization (policies, `Ash.can?`) | **Ash** |
| Action execution (`Ash.read`, `Ash.create`, `Ash.update`, `Ash.destroy`, `Ash.run_action`) | **Ash** |
| Data layer (ETS, Postgres, etc.) | **Ash** + adapters |
| Errors (`Ash.Error.Forbidden`, `Ash.Error.Invalid`) | **Ash** |
| Introspection (`Ash.Resource.Info`, `Ash.Domain.Info`) | **Ash** |

## What the host application owns

| Concern | Owner |
| --- | --- |
| Defining domains and resources | host app |
| Declaring agent modules with `use AshHarness.Agent` | host app |
| Wiring the orchestrator into a transport (HTTP, channel, CLI) | host app |
| Persisting checkpoints (DB, Redis, file system) | host app |
| Routing user messages to the right agent | host app |
| Rendering responses in the UI | host app |

## Boundaries this design intentionally enforces

1. **AshHarness does not call the LLM directly.** All LLM I/O goes through
   `jido_composer`'s orchestrator. We don't reimplement provider clients,
   parallel tool calls, streaming, or prompt caching — Jido does.

2. **AshHarness does not modify Ash behavior.** Resource and domain
   extensions are introspectable metadata only. A resource that uses
   `AshHarness.Resource` behaves identically to one that doesn't, except
   that it now exposes additional `AshHarness.Resource.Info` reads.

3. **AshHarness does not bypass Ash policies.** Every action invocation
   from the harness flows the actor through `Ash.can?` (at tool-exposure
   time, optionally) and through the actual call (at execution time,
   always). The agent literally cannot do anything its actor cannot do.

4. **The agent is not an Ash resource.** It does not live in a domain.
   It does not have a data layer. It is a behavioral declaration. If you
   want to persist agent state between sessions, that is the host
   application's job — model it as your own resource.

5. **Delegation does not transitively widen scope.** When agent A
   delegates to agent B, B operates strictly under B's declared scope,
   not A's. B returns text; A never sees B's records. (See ADR 0004.)
