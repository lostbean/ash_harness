# ADR 0001 — Jido Composer is the agent runtime

## Status

Accepted (2026-05-08).

## Context

The original spec defined `AshHarness.Harness` with its own session
struct, intent execution loop, telemetry, and an `AshHarness.LLM.Adapter`
behaviour. Effectively, an LLM orchestrator from scratch.

The user already maintains `jido_composer` (hex package, v0.5.x), which
provides:

- `Jido.Composer.Orchestrator` — LLM-driven loop with tools.
- `Jido.Composer.Skill` — packaged tool bundles.
- `Jido.Composer.Node.DynamicAgentNode` — dynamic skill assembly per
  query.
- HITL approval via `ApprovalRequest`/`ApprovalResponse`.
- Checkpointing for durable persistence.
- Native OpenTelemetry instrumentation.
- Provider transport via Jido AI underneath.

## Decision

`jido_composer` is the agent runtime. AshHarness builds **on** Jido,
not parallel to it.

## Consequences

### Removed from AshHarness

- `AshHarness.LLM.Adapter` behaviour — Jido owns transport.
- `AshHarness.LLM.Mock` — use Jido's `LLMStub`.
- Custom session loop in `AshHarness.Harness` — the harness is now a
  thin wrapper around Jido orchestrator construction and tool dispatch.
- Compaction engine — Jido's compaction (when present) covers it.

### Retained / unique to AshHarness

- DSL for declaring agents (identity / scope / behavior / delegation /
  constraints).
- Resource and domain extensions.
- Reachability graph + context renderer (Ash-shape-aware).
- Canonical schema derivation from Ash actions.
- Compile-time generation of `Jido.Action` modules and per-resource
  `Skill`s.
- Scope, mutation budget, reasoning, and confirmation gates that run
  inside the generated `Jido.Action.run/2`.
- Policy gate via `Ash.can?`.
- Repair loop (formats Ash validation errors for re-injection).
- Cross-agent delegation with text-only return.
- Three-layer eval framework.
- AshHarness telemetry events as Jido OTel span attributes / child events.

### Versioning

```
{:jido_composer, "~> 0.5"}
```

Major Jido bumps will require a matching AshHarness major bump. Document
the exact compat range in `mix.exs` and `README.md`.

### Risk

We're tied to one specific orchestrator library. If Jido stalls or
breaks, AshHarness inherits the pain. Mitigation: the gate pipeline and
Ash integration are independent of the orchestrator. We could swap to
another orchestrator with a focused refactor. Not worth designing for
that today.

## Alternatives considered

1. **Roll our own loop, depend on `langchain` for transport.**
   Rejected — duplicates work the user already shipped, more code to
   maintain, no specific advantage over Jido.
2. **Anthropic-only direct adapter.** Rejected — locks the library to
   one provider; Jido already covers multi-provider via Jido AI.
3. **Behaviour-first with multiple adapters.** Rejected — cleaner if it
   were our own loop, but the user has Jido. Don't add abstractions
   that aren't earning their cost.
