# Layer 11 — Telemetry

AshHarness emits `[:ash_harness, …]` `:telemetry` events and attaches
attributes to the surrounding Jido OpenTelemetry spans. Users get one
trace tree.

## Strategy (ADR — captured in 0001-jido-composer-as-runtime)

Jido already emits OTel spans for orchestrator/llm/tool calls. We do
**not** create our own root spans. Instead:

1. We emit `:telemetry` events for AshHarness-specific concerns.
2. We attach extra attributes (`ash_harness.*`) to the *active* Jido
   span at the time we emit them.

This gives users a single tree:

```
orchestrator (Jido)
├── llm.call (Jido)
├── tool.call ticket__assign (Jido)
│   └── ash_harness attributes:
│         scope.passed = true
│         policy.passed = true
│         budget.passed = true
│         action.executed = true
│         action.duration_ms = 12
```

## Event catalog

### Context rendering

```
[:ash_harness, :context, :rendered]
  measurements: %{render_time_ms, token_estimate, sections_count}
  metadata: %{agent, actor_id}
```

### Per-intent gate events

All five gates emit a `:checked` event on every evaluation (since
v0.1.2), regardless of pass or fail, so listeners can compute pass-rates
without OTel span sampling. The failure-class events (`:violation`,
`:missing`, `:exceeded`, `:denied`) still fire on the refusal path.
Every event metadata carries the shared `:request_id` so listeners can
correlate all telemetry within a single `GeneratedAction.dispatch/5`
call.

```
[:ash_harness, :scope, :checked]
  measurements: %{}
  metadata: %{agent, resource, action, passed: boolean, request_id}

[:ash_harness, :scope, :violation]
  metadata: %{agent, resource, action, request_id}

[:ash_harness, :reasoning, :checked]
  metadata: %{agent, resource, action, required: boolean, present: boolean, request_id}

[:ash_harness, :reasoning, :missing]
  metadata: %{agent, resource, action, request_id}

[:ash_harness, :confirmation, :requested]
  metadata: %{agent, resource, action, request_id}

[:ash_harness, :confirmation, :approved]
  metadata: %{agent, resource, action, respondent, duration_ms, request_id}

[:ash_harness, :confirmation, :rejected]
  metadata: %{agent, resource, action, respondent, request_id}

[:ash_harness, :budget, :checked]
  measurements: %{count, max}
  metadata: %{agent, resource, action, request_id}

[:ash_harness, :budget, :exceeded]
  metadata: %{agent, request_id}

[:ash_harness, :policy, :checked]
  metadata: %{agent, resource, action, passed: boolean, request_id}

[:ash_harness, :policy, :denied]
  metadata: %{agent, resource, action, ash_error_class, request_id}
```

### Action execution

```
[:ash_harness, :action, :executed]
  measurements: %{duration_ms, records_returned (read), records_changed (mutation)}
  metadata: %{agent, resource, action, status: :ok | :error,
              error_class: atom | nil, request_id}
```

### Repair loop

```
[:ash_harness, :repair, :feedback]
  measurements: %{attempt}
  metadata: %{agent, resource, action, reason_class, request_id}

[:ash_harness, :repair, :exhausted]
  metadata: %{agent, resource, action, total_attempts, request_id}
```

### Delegation

```
[:ash_harness, :delegation, :started]
  metadata: %{from_agent, to_agent, depth, request_id}

[:ash_harness, :delegation, :ended]
  measurements: %{duration_ms}
  metadata: %{from_agent, to_agent, status: :ok | :error, depth, request_id}

[:ash_harness, :delegation, :denied]
  metadata: %{from_agent, to_agent, reason, request_id}
```

### Eval

```
[:ash_harness, :eval, :scenario, :start]
  metadata: %{scenario, agent}

[:ash_harness, :eval, :scenario, :stop]
  measurements: %{duration_ms, tokens_used}
  metadata: %{scenario, agent, passed, gates_passed, gates_failed}

[:ash_harness, :eval, :gate, :checked]
  metadata: %{scenario, gate_kind, passed}

[:ash_harness, :eval, :report, :computed]
  metadata: %{scenario, report_kind, observations: map}
```

## OTel attribute additions

When AshHarness handles a tool call, it attaches these attributes to the
active span (typically Jido's `tool.call` span):

| Attribute | Type | Notes |
| --- | --- | --- |
| `ash_harness.agent` | string | agent module name |
| `ash_harness.resource` | string | resource module name |
| `ash_harness.action` | string | action atom as string |
| `ash_harness.scope.passed` | boolean | |
| `ash_harness.reasoning.required` | boolean | |
| `ash_harness.reasoning.present` | boolean | |
| `ash_harness.confirmation.required` | boolean | |
| `ash_harness.confirmation.outcome` | enum: pending\|approved\|rejected | |
| `ash_harness.budget.count` | int | mutation count after this action |
| `ash_harness.budget.max` | int | configured max |
| `ash_harness.policy.passed` | boolean | |
| `ash_harness.policy.error_class` | string \| nil | |
| `ash_harness.repair.attempt` | int | 0 on first try |
| `ash_harness.session.id` | string | session UUID |
| `ash_harness.request.id` | string | per-tool-call UUID |

## Subscribing

In the host app:

```elixir
:telemetry.attach_many(
  "my-app-ash-harness-handlers",
  [
    [:ash_harness, :scope, :violation],
    [:ash_harness, :policy, :denied],
    [:ash_harness, :budget, :exceeded],
    [:ash_harness, :action, :executed]
  ],
  &MyApp.AshHarnessHandler.handle_event/4,
  nil
)
```

## OTel exporter setup

We don't ship an exporter. Users wire whatever they already use for
Jido (`opentelemetry`, `opentelemetry_exporter`, etc.). The attributes
we add use the standard OTel semantic conventions where possible.

## Disabling

```elixir
config :ash_harness, :telemetry, enabled: false
```

When disabled, the harness skips `:telemetry.execute/3` calls. OTel
attribute additions also skip (no-op when no active span). Useful for
hot loops in tests.

## What we don't emit (deferred to v0.2)

- Per-token streaming events (Jido owns those when streaming arrives).
- Detailed input/output sampling (privacy-sensitive; opt-in only).
- Cost estimation (provider-dependent; out of scope).
