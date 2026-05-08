# Architecture — Data Flow

The lifecycle of a single agent invocation from user message to action
execution.

## End-to-end flow

```text
1. Host app receives user message
        │
        ▼
2. Host app calls AshHarness.Harness.new_session(MyAgent, opts)
        │  (resolves the actor; loads canonical tool list)
        ▼
3. AshHarness builds a Jido orchestrator
        │
        ├──► AshHarness.ContextRenderer.render(MyAgent)
        │     produces system prompt:
        │       identity / vocabulary / resources (top-level only)
        │       / traversal map / strategies / delegation hints / constraints
        │
        ├──► AshHarness.ToolGen.skills_for(MyAgent)
        │     returns [%Jido.Composer.Skill{}, ...]
        │     each Skill = one resource × its scoped actions
        │
        └──► Jido.Composer.Orchestrator built with system_prompt + skills
                                        + DynamicAgentNode for progressive disclosure
        │
        ▼
4. Host app calls AshHarness.Harness.run(session, user_message)
        │
        ▼
5. Jido orchestrator sends to LLM
        │
        ▼
6. LLM emits tool_use blocks (one or more, possibly parallel)
        │
        ▼
7. For each tool_use, AshHarness intercepts via the Jido.Action's run/2:
        │
        ├── 7a. Reverse-map tool name → (resource, action, input)
        │
        ├── 7b. ScopeGate.check  ─── if not in scope ──► :scope_violation
        │
        ├── 7c. ReasoningGate    ─── if required and missing ──► :reasoning_required
        │
        ├── 7d. ConfirmationGate ─── if confirm_before ──► Jido ApprovalRequest
        │                            ↳ host app presents to user
        │                            ↳ on approval, re-enter at 7e
        │
        ├── 7e. BudgetGate       ─── if mutation and budget exceeded ──► :mutation_limit_exceeded
        │
        ├── 7f. PolicyGate       ─── Ash.can?(actor, ...) ──► :policy_denied
        │
        ├── 7g. ActionExecutor   ─── Ash.read|create|update|destroy
        │                            with actor=session.actor
        │
        ├── 7h. Telemetry        ─── emit [:ash_harness, :action, :executed]
        │                            update Jido span with ash_harness.* attrs
        │
        ├── 7i. TrajectoryAppend ─── append %TrajectoryEntry{}
        │
        └──► result returned to Jido as Jido.Action {:ok, value} | {:error, ...}
        │
        ▼
8. Jido feeds tool_result back to LLM
        │
        ├─ on validation error: AshHarness.Repair formats the error
        │   → next turn the LLM sees the formatted feedback
        │
        ▼
9. Loop until LLM emits final assistant message OR budget exceeded
        │
        ▼
10. Host app receives the assistant message + the trajectory
```

## Compile-time data flow (one-time, per agent module)

```text
agent module                    Spark.Dsl pipeline
─────────────────────────       ────────────────────────────────────────

defmodule MyAgent do                ┌──────────────────────────────────┐
  use AshHarness.Agent              │ 1. parse DSL into entities       │
  identity do … end                 │    ─── Identity, Strategy,       │
  scope do … end                    │        ResourceEntry,            │
  behavior do … end                 │        DelegateEntry             │
  delegates_to do … end             └────────────────┬─────────────────┘
  constraints do … end                               │
end                                                  ▼
                                    ┌──────────────────────────────────┐
                                    │ 2. transformers (in order)       │
                                    │    a. ComputeReachability        │
                                    │       ─── persist :graph         │
                                    │    b. ComputeToolSet             │
                                    │       ─── for each ResourceEntry │
                                    │           build Canonical schema │
                                    │           persist :tool_list     │
                                    └────────────────┬─────────────────┘
                                                     │
                                                     ▼
                                    ┌──────────────────────────────────┐
                                    │ 3. verifiers (read-only)         │
                                    │    a. ScopeResourcesInDomains    │
                                    │    b. ScopeActionsExist          │
                                    │    c. ConfirmBeforeInScope       │
                                    │    d. AutoExecuteInScope         │
                                    │    e. ReasoningActionsInScope    │
                                    │    f. DelegatesUseAshHarness     │
                                    └────────────────┬─────────────────┘
                                                     │
                                                     ▼
                                    ┌──────────────────────────────────┐
                                    │ 4. ToolGen emits sibling modules │
                                    │    MyAgent.Tools.Ticket.Assign   │
                                    │    MyAgent.Tools.Ticket.Open     │
                                    │    MyAgent.Skills.Ticket          │
                                    │    MyAgent.Skills.Project         │
                                    └──────────────────────────────────┘
```

## Reachability flow

```text
agent scope:
  Ticket  → [:read, :open_ticket, :assign]
  Project → [:read]
  Member  → [:read, :by_workload]

Ticket annotations:                           ┌──────────────────────┐
  traversable [:project, :comments]           │  reachability graph: │
                                              │                      │
Project annotations:                          │  Ticket → Project    │
  traversable [:tickets]                      │  Ticket → Comment? ✗ │
                                              │     (Comment not in  │
Member annotations:                           │      scope, edge     │
  traversable []                              │      dropped)        │
                                              │                      │
                                              │  Project → Ticket    │
                                              │     (back-edge OK)   │
                                              │                      │
                                              │  Member: no edges    │
                                              └──────────────────────┘
```

## Progressive disclosure flow

The system prompt includes a *summary* of every in-scope resource and a
*meta-tool* `load_resource_skill(resource_name)` (provided by
`Jido.Composer.Node.DynamicAgentNode`'s skill registry).

```text
Initial context (always rendered):
  identity / vocabulary / resource summaries (1-2 lines each)
  / traversal map / strategies / delegation / constraints
  + meta-tool: load_resource_skill

Turn 1:
  LLM: "I need to assign a ticket. Let me load Ticket details."
  → calls load_resource_skill(:ticket)
  → AshHarness expands to full Ticket Skill (description, attributes,
    actions with hints, schema)
  → next turn the LLM sees the full Ticket detail in its context

Turn 2:
  LLM: ticket__assign(id: …, assigned_to: …)
  → tool intercepted, scope/reasoning/confirm/budget/policy/execute
```

## Why progressive disclosure matters

For an agent scoped over 12 resources with ~5 actions each, the eager
context can run 30k+ tokens. With progressive disclosure: the initial
context is ~3-5k, and only the resources the agent actually touches
expand into context.

## Telemetry emissions per request

| Event | When | Owner |
| --- | --- | --- |
| `[:jido_composer, :orchestrator, :start]` | session begins | Jido |
| `[:jido_composer, :llm, :call]` | each LLM call | Jido |
| `[:ash_harness, :scope, :violation]` | tool name not in scope | AshHarness |
| `[:ash_harness, :reasoning, :missing]` | required reasoning omitted | AshHarness |
| `[:ash_harness, :confirmation, :requested]` | gate triggers ApprovalRequest | AshHarness |
| `[:ash_harness, :confirmation, :approved/denied]` | response received | AshHarness |
| `[:ash_harness, :budget, :exceeded]` | mutation cap hit | AshHarness |
| `[:ash_harness, :policy, :denied]` | Ash.can? returns false | AshHarness |
| `[:ash_harness, :action, :executed]` | success or failure | AshHarness |
| `[:ash_harness, :repair, :feedback]` | validation error formatted | AshHarness |
| `[:ash_harness, :delegation, :started/ended]` | cross-agent | AshHarness |
| `[:ash_harness, :context, :rendered]` | renderer completes | AshHarness |
| `[:jido_composer, :tool, :call]` | each tool invocation | Jido |
| `[:jido_composer, :orchestrator, :stop]` | session ends | Jido |

The AshHarness events live as **child OTel spans** of the surrounding Jido
spans, so users get a single trace tree.
