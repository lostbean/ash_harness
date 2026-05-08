# Layer 09 — Delegation

Cross-agent delegation with an anti-corruption boundary. When agent A
delegates to agent B, B operates strictly under B's own scope and
returns text only — A never sees B's records.

## Why text-only return

Decision recorded in **ADR 0004**. Briefly: the alternative
(structured/typed returns) makes prompt-injection laundering across
agents trivially possible. By forcing the calling agent to receive
natural language only, the parent agent must re-parse and re-validate
before acting — which is the entire point of an anti-corruption layer.

This is *more cautious* than mainstream multi-agent frameworks (Swarm,
A2A, OpenAI Agents handoffs) — most of them share full conversation
state. v0.1.0 leans cautious; v0.2 may add a two-tier mode (structured
within trust zone, text across).

## DSL surface (already in agent layer)

```elixir
delegates_to do
  delegate MyApp.Agents.BillingAgent,
    for: "customer account status checks"
end
```

The natural-language `for:` description is rendered into agent A's
context as a delegation hint:

```
You can delegate to:
- BillingAgent — for customer account status checks
```

## How the agent invokes delegation

A meta-tool `delegate(target_agent_name, question)` is added to A's tool
list when `delegates_to` is non-empty. Calling it triggers
`AshHarness.Delegation.initiate/3` (host-app-mediated; see flow below).

## Flow

```text
Agent A's session                                Agent B's session
─────────────────                                ─────────────────

1. LLM calls delegate("BillingAgent",
                      "Is customer X in good standing?")
        │
        ▼
2. Delegation gate validates:
   - is BillingAgent in A's delegates_to list?     ── if not, error
   - resolve module (string → atom → module)
        │
        ▼
3. AshHarness.Delegation.initiate(A_session,
                                  BillingAgent,
                                  question)
        │
        ├──► render context for B (its own scope)
        ├──► assemble Jido orchestrator for B
        ├──► AshHarness.Harness.run(B_session, question)
        │                                                │
        │                                                ▼
        │                                       4. B answers — full reply text
        │                                                │
        │  ◄─────────── string only ─────────────────────┤
        │                                                │
        ▼
5. Delegation tool returns the string to A's
   tool result. A re-reasons over it.
```

## Public API

```elixir
defmodule AshHarness.Delegation do
  @doc """
  Initiate a delegation from `caller_session` to `target_agent_module`.
  Verifies the target is in the caller's delegates_to list. Builds a
  fresh session for the target and runs it with `question` as the user
  message.

  Returns the target's text reply, the target's trajectory (for
  observability/eval), and an updated caller session whose trajectory
  now includes a delegation entry.
  """
  @spec initiate(
    AshHarness.Harness.Session.t(),
    target_agent_module :: module(),
    question :: String.t(),
    opts :: keyword()
  ) ::
    {:ok, reply :: String.t(), updated_caller_session :: AshHarness.Harness.Session.t(),
     target_trajectory :: [AshHarness.Harness.TrajectoryEntry.t()]}
    | {:error, :delegation_not_permitted}
    | {:error, :delegation_depth_exceeded}
    | {:error, term()}
  def initiate(caller_session, target_agent_module, question, opts \\ [])
end
```

## Depth limit

To prevent infinite delegation chains, sessions track a `delegation_depth`
counter. The harness's `new_session/2` accepts an internal
`:_delegation_depth` opt; `Delegation.initiate/4` increments it for the
new session. Default cap is 3 (configurable via
`config :ash_harness, :delegation_max_depth`).

When exceeded, `initiate/4` returns `{:error, :delegation_depth_exceeded}`,
which the calling tool surfaces to the LLM as a string.

## What is and isn't shared

| Item | Shared with delegate? |
| --- | --- |
| The `question` (text) | yes — that's what's delegated |
| The caller's actor | **no** — the delegate uses its own actor (its own identity.actor) |
| The caller's records or query results | **no** — text-only |
| The caller's reasoning string | **no** — opaque to the delegate |
| Conversation history of the caller | **no** — fresh session for the delegate |
| Telemetry trace correlation | **yes** — both share the same OTel root span; delegate is a child span |
| Mutation count | **separate** — each session counts independently |

## Trajectory

The caller's trajectory gets one new entry of type
`:delegation`:

```elixir
%TrajectoryEntry{
  intent: %{type: :delegation, target: BillingAgent, question: "…"},
  result_status: :ok,
  data: %{reply_text: "…", target_trajectory_id: "…"},
  duration_ms: 1234,
  ...
}
```

The delegate's full trajectory is available separately (returned from
`initiate/4`) and is used by eval scenarios that want to assert against
delegate behavior.

## Telemetry

```
[:ash_harness, :delegation, :started]
  metadata: %{from_agent, to_agent, depth, request_id}

[:ash_harness, :delegation, :ended]
  measurements: %{duration_ms}
  metadata: %{from_agent, to_agent, status: :ok | :error, depth, request_id}

[:ash_harness, :delegation, :denied]
  metadata: %{from_agent, to_agent, reason: :not_permitted | :depth_exceeded}
```

## Errors

```elixir
defmodule AshHarness.Errors.DelegationNotPermitted do
  defexception [:from_agent, :to_agent, :message]
end

defmodule AshHarness.Errors.DelegationDepthExceeded do
  defexception [:from_agent, :to_agent, :depth, :max_depth, :message]
end
```

## Open questions

- **Should delegates support follow-up questions in the same flow?**
  v0.1.0: no. Each `delegate(...)` call is a one-shot. If A needs more,
  it issues another delegation. This keeps the boundary clean — no
  cross-session state to leak.
- **Should we render the delegate's *trajectory summary* back to A?**
  v0.1.0: no. A only sees the reply. Trajectories are for
  observability and eval, not for A's reasoning.
- **Two-tier mode (structured returns within trust zone)?** v0.2. The
  trust-zone concept needs more thought before we ship it.
- **Can a delegate refuse?** Yes — the delegate may answer "I cannot do
  this; you should try X." That's a normal response, not a special
  error.
