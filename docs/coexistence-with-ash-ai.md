# Co-existence with ash_ai

AshHarness and `ash_ai` solve overlapping problems with different
opinions. They can co-exist in the same project.

## AshHarness leads with…

- Agent-as-first-class entity (the `use AshHarness.Agent` module).
- Scope-as-DSL (compile-time list of (resource, action) pairs).
- Eval-first design (`use AshHarness.Eval`, pass/fail gates).
- Jido-backed runtime (use existing `jido_composer` orchestration).

## ash_ai leads with…

- Tighter integration into ash_ai's own toolset and conventions.
- Different opinions on prompts, RAG, and tool emission.

(See ADR 0010 and `design/adrs/0010-position-vs-ash-ai.md` for the
positioning rationale; verify against `ash_ai`'s current state before
publishing — open question #1.)

## Using both

AshHarness operates on Ash resources directly. If your project uses
`ash_ai` features (e.g., its prompt helpers, embedding integrations,
or AI-typed attributes), those still work — AshHarness just doesn't
depend on them.

If you want an agent driven by AshHarness's harness over resources
that also have `ash_ai` extensions, declare both extensions on the
resource:

```elixir
defmodule MyApp.Ticket do
  use Ash.Resource,
    domain: MyApp.Ticketing,
    extensions: [AshHarness.Resource, AshAi.SomeExtension]

  agent_annotations do
    description "..."
  end
end
```

The two extensions don't conflict; they persist into different keys.
