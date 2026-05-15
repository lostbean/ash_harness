# ADR 0005 — Tool generation: hybrid (compile-time + runtime dynamic)

## Status

Accepted (2026-05-08).

## Context

How do we map Ash actions to LLM tools?

Three options on the table:

1. Compile-time `Jido.Action` module per action.
2. One generic dynamic adapter `Jido.Action` parameterized by tool
   name + input.
3. Compile-time per-resource `Skill` bundles.

Real-world need: a project may want **session-scoped tools** that don't
exist at compile time. Examples:

- A "submit_for_review" tool that only appears when the agent has an
  unsaved draft in its session state.
- A "select_assignee" tool whose enum is filtered by the actor's
  visibility (so the choices are session-dependent, not static).
- Composing AshHarness with another library that wants to inject its
  own tool at session start.

## Decision

Hybrid approach:

1. **Default path (compile-time)**: at `use AshHarness.Agent`, generate
   one `Jido.Action` module per scoped (resource, action) pair, packed
   into one `Jido.Composer.Skill` per resource.
2. **Escape hatch (runtime)**: `AshHarness.Tool.dynamic/2` builds an
   additional **`AshHarness.Tool.t()`** wrapper at session-start time
   carrying the schema, the dispatch target `(resource, action)`, and an
   optional `input_builder`. The wrapper routes through
   `AshHarness.Harness.GeneratedAction.dispatch/5` (same path as
   compile-time `Jido.Action` modules), so it sees the same gates and
   the same telemetry. The signature is
   `dynamic(keyword(), keyword()) :: AshHarness.Tool.t()`.

Both flow through the **same** scope/reasoning/budget/policy/executor
pipeline. The runtime API does not bypass any gate.

## Consequences

### Pros

- 90% of cases are compile-time: validation, debuggable stack traces,
  fast.
- 10% of cases (session-conditional, finalizers) have a clean API.
- One pipeline, two entry points — no behavior duplication.

### Cons

- Two ways to define a tool means two test surfaces.
- Dynamic tools cannot be type-checked at compile time, so users must
  test them.

### What this is *not*

- Not a way to widen the agent's scope at runtime. Dynamic tools are
  still subject to scope gates; they call Ash actions that must be in
  the agent's static `scope` block.
- Not a runtime DSL. The agent declaration is still compile-time.

## Examples

### Compile-time (the default)

```elixir
defmodule MyAgent do
  use AshHarness.Agent, domains: [MyApp.Sales]

  scope do
    resource Order do
      actions [:read, :place, :cancel]
    end
  end
end

# Generated:
# - MyAgent.Tools.Order.Read
# - MyAgent.Tools.Order.Place
# - MyAgent.Tools.Order.Cancel
# - MyAgent.Skills.Order  (with all three tools)
```

### Runtime dynamic

```elixir
session = AshHarness.Harness.new_session(MyAgent,
  extra_tools: [
    AshHarness.Tool.dynamic("order__finalize_draft",
      description: "Finalize the unsaved draft as a real order.",
      schema: [reason: [type: :string, required: true]],
      resource: MyApp.Sales.Order,
      action:   :place,
      input_builder: fn input, session ->
        Map.merge(session.metadata.draft, input)
      end
    )
  ]
)
```

## Alternatives considered

1. **Compile-time only.** Rejected — kills the finalizer use case.
2. **Runtime only.** Rejected — loses the compile-time validation that
   makes Ash a joy.
3. **Single dynamic adapter Action that takes a tool name + input.**
   Rejected — unhelpful stack traces, weak schema validation,
   confusing for new users.
