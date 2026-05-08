# Architecture — Jido Composer Integration

This document is the contract between AshHarness and `jido_composer`.
Read it before modifying anything in `lib/ash_harness/harness/`.

## What `jido_composer` provides

Confirmed from the `jido_composer` 0.5.x README and source layout:

| Module | What it does | AshHarness use |
| --- | --- | --- |
| `Jido.Action` | A tool. `use Jido.Action, name:, description:, schema:` + `run/2`. | We generate one per scoped Ash action. |
| `Jido.Composer.Skill` | A bundle: `%Skill{name, description, prompt_fragment, tools}` | We generate one per scoped Ash resource. |
| `Jido.Composer.Skill.assemble/2` | Build an orchestrator from a skill list. | The harness uses this to assemble per-session orchestrators. |
| `Jido.Composer.Skill.BaseOrchestrator.query_sync/2` | Run an assembled orchestrator with a user message. | The harness's `run/2` delegates here. |
| `Jido.Composer.Orchestrator` | `use Jido.Composer.Orchestrator, name:, model:, nodes:, system_prompt:` | We can also produce module-form orchestrators when we want compile-time tool sets. |
| `Jido.Composer.Node.DynamicAgentNode` | Parent-delegated skill selection — the parent LLM picks which skills to equip a sub-agent with. | This is our **progressive disclosure** mechanism (see ADR 0007). |
| `Jido.Composer.Node.HumanNode` | Pause for human decision. | The host app uses this directly when the agent is part of a larger Composer workflow. |
| `Jido.Composer.HITL.ApprovalRequest` / `ApprovalResponse` | Tool approval protocol. | This is what `confirm_before` actions emit. |
| `Jido.Composer.Checkpoint` | Serialize a running/suspended flow for resume. | Available but not required for v0.1.0. |
| OpenTelemetry instrumentation throughout `Orchestrator.Obs`, `Workflow.Obs`. | Native. | We append `ash_harness.*` attributes to active spans. |
| `Jido.Composer.Skill.assemble/2` plus `DynamicAgentNode` | Skill-based dispatch. | Combined: per-resource Skills, dispatched dynamically. |

## What AshHarness builds on top

AshHarness produces, for each agent module, the following at compile time:

```text
MyAgent
├── MyAgent.Tools.<Resource>.<Action>     (one Jido.Action per scoped action)
└── MyAgent.Skills.<Resource>             (one %Skill{} per scoped resource)
```

At session start, AshHarness assembles a Jido orchestrator:

```elixir
{:ok, orchestrator} = Jido.Composer.Skill.assemble(
  agent_skills(MyAgent),                      # the per-resource Skills
  base_prompt: AshHarness.ContextRenderer.render(MyAgent).full_text,
  model: model_for(MyAgent),
  extra_nodes: [progressive_disclosure_node(MyAgent)]
)
```

`progressive_disclosure_node/1` is a `DynamicAgentNode` whose
`skill_registry` is the agent's full skill set — so the LLM can pick which
resource skills to load for any given sub-question.

## How AshHarness intercepts tool calls

Each generated `Jido.Action` has a `run/2` that does:

```elixir
@impl Jido.Action
def run(input, ctx) do
  session = ctx[:ash_harness_session]   # injected by harness
  intent  = %Intent{
    resource: @resource_module,
    action:   @action_name,
    input:    input,
    reasoning: input[:_reasoning],
    request_id: ctx[:request_id]
  }

  with :ok <- ScopeGate.check(session, intent),
       :ok <- ReasoningGate.check(session, intent),
       :ok <- ConfirmationGate.check(session, intent),   # may suspend → ApprovalRequest
       :ok <- BudgetGate.check(session, intent),
       :ok <- PolicyGate.check(session, intent) do
    case ActionExecutor.run(session.actor, intent) do
      {:ok, result}   -> {:ok, render_result(result)}     # success
      {:error, error} -> {:error, Repair.format_feedback(error)}  # back to LLM
    end
  else
    {:halt, :confirmation_required, request} -> {:halt, request}  # Jido HITL
    {:error, reason} -> {:error, Repair.format_feedback(reason)}
  end
end
```

Note the `ConfirmationGate` returns `{:halt, request}` which integrates
with Jido's suspension protocol — the orchestrator suspends, emits a
`Jido.Composer.HITL.ApprovalRequest`, and resumes when the host app
provides an `ApprovalResponse`.

## The session struct

`AshHarness.Harness.Session`:

```elixir
%AshHarness.Harness.Session{
  agent: MyAgent,
  actor: %User{...},
  trajectory: [%TrajectoryEntry{...}],
  mutation_count: 0,
  turn_number: 0,
  jido_orchestrator: %Jido.Composer.Orchestrator.State{...},
  request_id: "req_…",
  rendered_context: %AshHarness.RenderedContext{...},
  options: keyword()
}
```

The session is passed to Jido orchestrator calls via the orchestrator's
context map. AshHarness's gates read it; the action executor reads it; the
trajectory append writes back into it.

## What we explicitly delegate to Jido

- **LLM calls**: prompt formatting, retry on transport errors, parallel tool
  use, prompt caching headers, model selection.
- **Tool dispatch**: invoking the `Jido.Action.run/2` per tool_use block.
- **HITL plumbing**: emitting and consuming approval requests.
- **Checkpointing**: when host app needs to persist mid-flow.
- **OTel spans**: orchestrator/llm/tool spans created automatically.
- **Streaming** (when supported): emitted from Jido.

## What we explicitly do *not* delegate to Jido

- **Authorization** (Ash policies + scope) — must run in our `run/2`,
  before the action executes.
- **Budget enforcement** — we count mutations; Jido has session-level
  caps (`max_turns`) but not per-turn write caps.
- **Repair feedback formatting** — Ash error structures are specific to
  Ash, so we own the formatting back to the LLM.
- **Trajectory shape** — we capture per-action records with reasoning,
  policy outcome, repair attempts; this richer than Jido's per-tool spans.

## Failure modes at the boundary

| Scenario | Where it surfaces | Handling |
| --- | --- | --- |
| `Jido.Action.run/2` returns `{:error, reason}` | Jido feeds reason as tool_result text to LLM | We format `reason` via `Repair.format_feedback/1`. |
| Halt with `{:halt, request}` | Jido suspends orchestrator with `SuspendForHuman` directive | Host app sees `ApprovalRequest`; on response, orchestrator resumes. |
| Ash.can? raises (config error) | Bubbles through Jido as crash | Catch in PolicyGate, return `{:error, %PolicyDenied{...}}`. |
| Jido transport error to LLM | Jido retry policy applies | We don't intervene; trajectory records the gap. |
| Jido returns malformed tool input | Generated `Jido.Action` schema validation rejects | Returns `{:error, validation_error}` → Repair feedback. |

## Versioning

- AshHarness depends on `{:jido_composer, "~> 0.5"}` for v0.1.0.
- ADR 0001 records the choice. Major Jido version bumps require a
  matching AshHarness major bump.
