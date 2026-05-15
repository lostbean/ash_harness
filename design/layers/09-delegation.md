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
    as: "billing",
    purpose: "customer account status checks"
end
```

The `as:` value (required since v0.1.2) is the case-insensitive alias
the LLM passes to the `delegate` skill — it picks the matching entry
out of the agent's `delegates_to` list. A compile-time verifier
(`AshHarness.Agent.Verifiers.DelegateAliasesUnique`) rejects duplicate
aliases. The natural-language `purpose:` description is rendered into
agent A's context as a delegation hint:

```
You can delegate to:
- BillingAgent (as "billing") — for customer account status checks
```

## How the agent invokes delegation

`AshHarness.Delegation.Skill` is a single dynamic `Jido.Action` taking
`(target: string, question: string)`. It's appended to the
orchestrator's tool list — by `OrchestratorFactory.build/1` and the
generated `tool_nodes/0` — whenever the agent's `delegates_to` is
non-empty. The skill is **not** gated by `requires_approval`.

When the LLM invokes the skill:

1. The skill resolves `target` against the agent's `:as` aliases
   (case-insensitive exact match). On no match it returns
   `{:error, "Unknown delegate target '<target>'. Available aliases:
   <list>"}` so the LLM sees a clean error tool result.
2. On match it calls `AshHarness.Delegation.initiate/4`.
3. The skill forwards a small subset of the parent session's opts —
   `[:req_options, :temperature, :max_tokens, :max_iterations]` — to
   the child. This is what makes a host that wires an LLM stub for
   the parent see the same stub on the child (LLMStub-backed tests
   work end-to-end without per-agent fixtures).
4. On `{:error, :delegate_halted}` (the child suspended on its own
   HITL) the skill returns
   `{:error, "delegate halted: requires confirmation"}` — the
   nested-HITL deferral described in
   `openspec/changes/audit-followup-v0-1-2/design.md`. The host
   agent's LLM sees a string tool error; the child's suspension stays
   on the child. Multi-tier approval workflows are v0.2.

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
    | {:error, %AshHarness.Errors.DelegationNotPermitted{}}
    | {:error, %AshHarness.Errors.DelegationDepthExceeded{}}
    | {:error, :delegate_halted}
    | {:error, term()}
  def initiate(caller_session, target_agent_module, question, opts \\ [])
end
```

Since v0.1.2 the function lives in `AshHarness.Delegation.Initiate` and
`AshHarness.Delegation.initiate/4` is a thin re-export. The error path
returns the structured `%DelegationNotPermitted{from, to, reason}` /
`%DelegationDepthExceeded{from, to, depth, max_depth}` structs.
`:delegate_halted` is an internal atom — the LLM-facing skill
translates it to text (see "How the agent invokes delegation").

## Depth limit

To prevent infinite delegation chains, sessions track a `delegation_depth`
counter. The harness's `new_session/2` accepts an internal
`:_delegation_depth` opt; `Delegation.initiate/4` increments it for the
new session. Default cap is 3 (configurable via
`config :ash_harness, :delegation_max_depth`).

When exceeded, `initiate/4` returns
`{:error, %AshHarness.Errors.DelegationDepthExceeded{from, to, depth,
max_depth}}`, which the delegation skill surfaces to the LLM as a
string (the struct's `Exception.message/1`).

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
  defexception [:from, :to, :reason]
end

defmodule AshHarness.Errors.DelegationDepthExceeded do
  defexception [:from, :to, :depth, :max_depth]
end
```

Both modules live under `lib/ash_harness/errors/` and are part of the
seven-struct errors tree (`AshHarness.Errors.classify/1` maps them to
their Splode class). `Exception.message/1` produces the human-readable
text the delegation skill surfaces to the LLM.

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
