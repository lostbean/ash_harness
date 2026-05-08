# Coming from LangGraph / Swarm / OpenAI Agents SDK

This guide is for engineers who have built agents in Python frameworks and
are looking at AshHarness for the first time. It maps familiar concepts to
their Ash/Elixir equivalents and highlights what's the same and what's
different.

## Mental model translation

| You know it as | In AshHarness | Notes |
| --- | --- | --- |
| Tool / Function | `Jido.Action` (one per Ash action), packaged in `Jido.Composer.Skill` | Auto-generated from Ash actions; you never hand-write tool schemas. |
| System prompt | Output of `AshHarness.ContextRenderer.render/2` | Derived from the agent DSL + resource annotations. You write the metadata; we render. |
| Agent / Assistant | A module that uses `AshHarness.Agent` | Declarative; not an instance. Identity, scope, behavior are the source. |
| Handoff (Swarm) | `delegates_to` block + `AshHarness.Delegation.initiate/3` | Stricter: text-only return, separate scope. See ADR 0004. |
| Tool approval (Cursor / Aider) | `confirm_before` in `behavior` | Implemented via Jido's `ApprovalRequest`/`ApprovalResponse`. |
| Memory / scratchpad | Not in v0.1.0 | The conversation history Jido maintains is your memory. Persistent cross-session memory is host-app responsibility. |
| Tool retries on validation | **Repair Loop** (`AshHarness.Harness.Repair`) | Ash validation errors are formatted and re-fed to the LLM. |
| Guardrails | Scope (DSL) + Ash policies + budget + reasoning requirements | Multi-layer; the agent literally cannot see tools its actor isn't authorized for. |
| State machine (LangGraph) | Out of v0.1.0 scope. Use `Jido.Composer.Workflow` directly if needed. | AshHarness is the orchestrator (LLM-driven loop) side. |
| Provider abstraction | Jido handles it under `model: "anthropic:claude-…"` strings | We never define our own LLM adapter behaviour. |
| Observability | OpenTelemetry, automatic via Jido | We add `[:ash_harness, …]` child events. |

## What's the same

- **Tool-call loop**: the model sees a tool list, picks one, gets a result,
  picks the next tool. AshHarness inherits this from `jido_composer`'s
  orchestrator.
- **Parallel tool use**: enabled by default (Jido respects model defaults).
- **Streaming**: supported via Jido (when AshHarness ships streaming
  consumers in a later version).
- **Per-tool descriptions**: still the highest-leverage thing to write
  carefully. AshHarness reads them from `agent_annotations.hint`.

## What's different

### 1. Resources are first-class

In LangGraph/Swarm, your "things in the world" are implicit: an agent
calls `query_orders(customer_id)` and gets back a list. There's no
declared schema for what an Order *is*; the model infers it from tool
output.

In AshHarness, an `Order` is an Ash resource with attributes,
relationships, validations, and policies. The agent's context **describes
the Order** before the agent calls anything. The model knows the schema
shape before it sees data.

This means: better tool-call accuracy, smaller tool descriptions (the
description is "delegate work" not "delegate work given the following
schema for Member …"), and the same source of truth for your REST API,
your auth, and your agent.

### 2. Authorization is enforced, not advisory

In Python frameworks, the agent's permissions are usually a list of
allowed tool names. If a tool's underlying function reads from a database
based on `user_id`, you trust the function to enforce.

In AshHarness:
- The DSL `scope` block enumerates what's *visible* (no tool exists for
  things outside scope).
- The `actor` flows into every Ash call; Ash policies enforce at the data
  layer.
- The harness calls `Ash.can?` before execution and returns a structured
  `:policy_denied` if no.

You cannot accidentally invoke a tool that exposes data the actor isn't
allowed to see, because Ash refuses. You also cannot execute a write that
the actor isn't allowed to make.

### 3. Compile-time, not runtime, derivation

LangGraph builds graphs at runtime. Swarm wires handoffs at runtime.
AshHarness derives **everything possible at compile time**:

- Tool modules and schemas: emitted by macros at agent-module compile.
- Reachability graph: persisted into DSL state.
- Validation: scope mismatches caught at `mix compile`, not at first
  request.

If your scope references a non-existent action, the build fails with a
specific error message. You don't discover it when an agent runs in
production.

### 4. The host app owns the loop wiring

In Anthropic's Claude Agent SDK and Python SDKs, you run an "agent loop"
function. AshHarness does *not* run a long-lived process. Instead:

- The host app receives a user message (HTTP, WebSocket, CLI).
- It calls `AshHarness.Harness.run(session, message)`.
- That call returns the assistant's reply + the trajectory + an updated
  session.
- The host app persists the session if needed (or relies on Jido's
  checkpointing).

This matches Phoenix's request/LiveView model. There is no daemon. There
is no "kill the agent" — there is no agent process to kill.

### 5. Evals are gated, not weighted-averaged

Many Python frameworks compute a composite eval score. AshHarness
intentionally rejects this:

- `gate :resource_state` — must pass; if it fails, the scenario fails.
- `report :trajectory`, `report :qualitative` — diagnostic; surface in
  the run output but never paper over a gate failure.

See ADR 0002 for the reasoning.

## A side-by-side hello world

### LangGraph (sketch)

```python
from langgraph.graph import StateGraph

graph = StateGraph(AgentState)
graph.add_node("triage", lambda s: call_llm_with_tools(s, [
    Tool("read_tickets", ...),
    Tool("assign_ticket", ...),
]))
graph.add_edge(...)
agent = graph.compile()
```

### AshHarness

```elixir
defmodule MyApp.Agents.TriageAgent do
  use AshHarness.Agent, domains: [MyApp.Ticketing]

  identity do
    name "Triage"
    description "Processes incoming tickets and assigns ownership."
    actor MyApp.Agents.Actors.triage_bot()
  end

  scope do
    resource MyApp.Ticketing.Ticket do
      actions [:read, :assign]
    end
  end

  behavior do
    confirm_before [:assign]
    auto_execute [:read]
  end

  constraints do
    max_mutations_per_turn 5
    require_reasoning_for [:assign]
  end
end

# In a Phoenix controller:
session = AshHarness.Harness.new_session(MyApp.Agents.TriageAgent)
{reply, session} = AshHarness.Harness.run(session, user_message)
```

The Ash resource `MyApp.Ticketing.Ticket` already has actions, validations,
and policies. AshHarness reads them; the agent module doesn't repeat them.

## When AshHarness is the wrong choice

- You don't have a domain model — you're building a research/Q&A agent
  with no operational state. AshHarness's value is the resource graph;
  if there are no resources, use Jido AI directly or stick with Python.
- You need workflows (deterministic pipelines, fan-out, etc.) more than
  agentic loops. Use `Jido.Composer.Workflow` directly; AshHarness is
  the LLM/orchestrator side.
- Your Ash resources are heavily generic-action-shaped (no CRUD), and the
  agent needs structured operations not surfaced as actions. Less
  friction, but think through whether the actions belong on the resource
  anyway.
