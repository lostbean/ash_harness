# AshHarness

Turn Ash Framework resources into the operating layer for AI agents
driven by `jido_composer`. One source of truth for what the agent can
do (Ash actions) and what it's allowed to do (Ash policies).

## Why

If you've built agents with LangGraph or Swarm, you wrote the tools,
the schemas, and the authorization checks separately from your domain
model. They drifted. AshHarness fixes this by deriving the agent's
tool surface, schema, and gate pipeline from the same Ash resources
your application already uses.

## Quickstart

Add the dependency:

```elixir
def deps do
  [
    {:ash_harness, "~> 0.1.0"}
  ]
end
```

Annotate an Ash resource with `AshHarness.Resource`:

```elixir
defmodule MyApp.Ticket do
  use Ash.Resource,
    domain: MyApp.Ticketing,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description "A unit of work in the support queue."
    traversable [:project, :comments]
    hidden_attributes [:internal_notes]
    hint :assign, "Use this to delegate work to a teammate."
  end

  # ... attributes, actions, relationships, policies ...
end
```

Declare an agent:

```elixir
defmodule MyApp.TriageAgent do
  use AshHarness.Agent, domains: [MyApp.Ticketing]

  identity do
    name "TriageBot"
    description "Triages incoming support tickets."
    actor &MyApp.bot_actor/0
    model "anthropic:claude-sonnet-4-5"
  end

  scope do
    resource MyApp.Ticket do
      actions [:read, :open_ticket, :assign]
    end
  end

  behavior do
    confirm_before [:assign]
    auto_execute [:read, :open_ticket]
  end

  constraints do
    max_mutations_per_turn 10
    require_reasoning_for [:assign]
  end
end
```

Run a turn:

```elixir
{:ok, session} = AshHarness.Harness.new_session(MyApp.TriageAgent)
{:ok, reply, session} = AshHarness.Harness.run(session, "Hello")
```

## What you get

- **Compile-time tool generation**: one `Jido.Action` module per scoped
  action; one `Jido.Composer.Skill` per scoped resource. The agent's
  tool surface is derived from the resource/action definitions, not a
  separate registration step.
- **Canonical schema, three renderers**: derive an
  `%AshHarness.Schema.Canonical{}` once, render to Anthropic / OpenAI /
  MCP via pure functions.
- **Gate pipeline**: scope → reasoning → confirmation → budget → policy.
  Authorization is enforced inside the generated tool, before any Ash
  mutation, via `Ash.can?` and the resource's policy block.
- **Confirmation halts**: actions in `confirm_before` surface as Jido
  `ApprovalRequest`s for the host application to mediate.
- **Per-turn mutation budget**: counts successful create/update/destroys
  per turn; reads don't count; failed mutations don't count.
- **Repair loop**: formats Ash validation errors into LLM-readable
  feedback; classifies retryable vs. terminal failures.
- **Delegation**: cross-agent text-only return with anti-corruption
  boundary (delegate uses its own actor; delegate's records never
  leak to the caller).
- **Telemetry**: `[:ash_harness, ...]` events for every gate and
  every action execution; OTel attribute attachment to active spans.
- **Eval framework**: declarative scenarios with pass/fail gates
  (`gate :resource_state`, `gate :invariant`) and diagnostic reports
  (`report :trajectory`, `report :qualitative`). No composite weighted
  score — pass/fail is binary (ADR 0002).

## Testing eval scenarios

`AshHarness.Eval.Runner` drives scenarios end-to-end against the real
agent. LLM HTTP traffic is recorded/replayed via
[`req_cassette`](https://hex.pm/packages/req_cassette) so default
`mix test` is deterministic and never hits the network.

Cassettes live at
`test/cassettes/<module-snake-case>/<scenario-snake-case>.json` and
are committed to source control. The recording mode is controlled by
`ASH_HARNESS_CASSETTE_MODE`:

| Mode      | Behaviour                                                       |
| --------- | --------------------------------------------------------------- |
| (default) | `replay` — fail loudly on missing cassettes                     |
| `record`  | hit the real LLM and write any missing cassettes                |
| `bypass`  | hit the real LLM without recording (debug only)                 |

To re-record a single cassette:

```bash
rm test/cassettes/my_eval/scenario.json
ASH_HARNESS_CASSETTE_MODE=record mix test test/my_eval_test.exs
```

## Documentation

- `design/README.md` — architecture, ADRs, layer specs.
- `docs/coming-from-langgraph-swarm.md` — mental-model map for
  LangGraph/Swarm users.
- `docs/coexistence-with-ash-ai.md` — using both libraries together.
- `benchmarks/tau_bench_airline/` — τ-bench airline-domain port and
  reproducible results.

## Status

v0.1.0 is the first release. The public API is in
`design/implementation/public-api.md`; stable across v0.1.x patches.
DynamicAgentNode-based progressive disclosure is deferred to v0.2
(see Phase 0 notes in
`openspec/changes/bootstrap-ash-harness-v0-1-0/tasks.md`).
