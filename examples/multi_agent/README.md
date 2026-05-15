# Multi-Agent Example

Supervisor + delegate pattern: a coordinator agent that delegates to
specialist agents based on the user's question.

```elixir
defmodule MyApp.CoordinatorAgent do
  use AshHarness.Agent, domains: [MyApp.Sales, MyApp.Support]

  identity do
    name "Coordinator"
    description "Routes user questions to the right specialist."
    actor &MyApp.bot_actor/0
  end

  scope do
    resource MyApp.Conversation do
      actions [:read]
    end
  end

  delegates_to do
    delegate MyApp.AccountAgent, "Account-management questions."
    delegate MyApp.SupportAgent, "Reservation / ticket questions."
  end
end
```

Each delegate is fully isolated:

- Has its own `identity.actor` (the coordinator's actor is NOT propagated).
- Uses its own scope; the coordinator can't see the delegate's records.
- Returns a text-only reply (no structured data, no shared trajectory).
- Counts mutations against its own budget.

Depth is capped at 3 by default (configurable via
`config :ash_harness, :delegation_max_depth, N`).

See `AshHarness.Delegation` for the API and ADR 0004 for the rationale
behind the text-only return shape.

## Runnable demo

A self-contained script that exercises the introspection surface (no
LLM required) is shipped in this directory. It uses the
`AshHarness.Test.DelegatingAgent` from the test support tree, which
declares `delegates_to AshHarness.Test.TriageAgent`. Run from the
repository root:

```
mix run examples/multi_agent/run.exs
```

It prints the caller's declared delegates, the actor / scope isolation
between caller and target, the `delegate` meta-tool that ToolGen emits
when `delegates_to` is non-empty, and the current depth cap.
