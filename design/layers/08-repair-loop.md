# Layer 08 — Repair Loop

**Renamed from "Ralph Loop" in the original spec.** The pattern:
when an Ash action fails validation, format the error in a way the LLM
can act on and re-feed it as the tool result. The next turn the model
issues a corrected call.

## Why this is its own layer

Ash error structures are domain-specific. A `%Ash.Error.Invalid{}` may
contain nested changeset errors, validation messages, and constraint
violations. Surfacing these well to an LLM raises tool-call success rates
significantly. We own the formatting because Ash is our integration
surface — Jido sees only the final string.

## Public API

```elixir
defmodule AshHarness.Harness.Repair do
  @doc """
  Formats an Ash validation/policy error into a string suitable for
  re-injection as a tool_result.
  """
  @spec format_feedback(any()) :: String.t()
  def format_feedback(error)

  @doc """
  True if the error class supports retry-with-correction.
  Validation errors: yes.
  Policy denials: no (correcting input won't help).
  Transport errors: yes (the harness itself does not retry, but the
  LLM may rephrase).
  """
  @spec retryable?(any()) :: boolean()
  def retryable?(error)
end
```

## Output format

For a validation error:

```
Action `ticket__assign` failed validation.

Errors:
- assigned_to: must not be nil
- assigned_to: must reference a Member where active = true
- status: cannot transition from :resolved to :in_progress

Please fix the input and try again. The action's accepted parameters are:
  id (uuid, required), assigned_to (uuid, required)
```

For a policy denial (not retryable, but informative):

```
Action `ticket__destroy` was denied by policy.

The actor (id=agent-001, role=triage_bot) is not authorized to destroy tickets.
Reason: only the ticket creator or a manager may destroy.

You should not attempt this action again with the same actor. Consider
delegating to an agent with sufficient authority.
```

For a transport error (rare, surfaced for completeness):

```
Action `ticket__assign` failed at the transport layer: timeout after 30s.
Try again, or break the operation into smaller steps.
```

## Where retry actually happens

The repair loop is **not a loop in the harness**. The "loop" is the
orchestrator's natural model-tool-result cycle: the model issues a
call, gets back our formatted string, and decides on the next call.

What the harness *does* track:

- `repair_attempts` per `(resource, action)` within a session.
- A cap (`max_repair_loop_retries`) — when reached, subsequent
  attempts on the same action return `:error` with "you have already
  retried this action N times; consider a different approach."

This caps runaway loops where the model keeps trying the same broken
input.

## Format details

### Changeset error walking

Ash returns `%Ash.Error.Invalid{errors: [...]}`. We walk this and emit
one bullet per error, formatted as `field: human-message`. For errors
without a field (general changeset errors), emit them under `general:`.

### Including the schema reminder

Every formatted error includes the action's accepted parameters list
(name + type + required) at the bottom. This lets the LLM correct the
*shape* even if it forgot the schema since the original tool description.

### Stripping internal info

We never include:

- Stack traces.
- Module names of validators / changes.
- Internal Ash error class names.
- Database error codes.

The agent should see semantic descriptions, not implementation details.

## Example formatter behavior

Input:

```elixir
%Ash.Error.Invalid{
  errors: [
    %Ash.Error.Changes.InvalidArgument{
      field: :assigned_to,
      message: "must not be nil"
    },
    %Ash.Error.Changes.InvalidAttribute{
      field: :status,
      message: "cannot transition from :resolved"
    }
  ]
}
```

Output:

```
Action `ticket__assign` failed validation.

Errors:
- assigned_to: must not be nil
- status: cannot transition from :resolved

Please fix the input and try again. The action's accepted parameters are:
  id (uuid, required), assigned_to (uuid, required)
```

## When *not* to repair

Some failures don't benefit from repair feedback:

| Error class | Format and re-feed? |
| --- | --- |
| Validation (`Ash.Error.Invalid`) | yes |
| Policy (`Ash.Error.Forbidden`) | yes, marked non-retryable |
| Transport / DB connection | yes, marked retryable |
| Configuration error (e.g., resource has no such action) | no — this is a developer bug; raise to host app |
| Unexpected exception | no — re-raise; the orchestrator's error handler decides |

Configuration errors and unexpected exceptions surface as `{:error, …}`
to the host, not as a tool result. If we silently format them, the agent
will spend turns trying to "fix" something that isn't its problem.

## Telemetry

```
[:ash_harness, :repair, :feedback] %{count: 1}
  metadata: %{agent: ..., resource: ..., action: ..., reason_class: :validation | :policy | :transport}
[:ash_harness, :repair, :exhausted] %{count: 1}
  metadata: %{agent: ..., resource: ..., action: ..., attempts: N}
```

## Open questions

- **Per-attempt feedback differentiation:** should the second attempt's
  feedback include "you already tried X with input Y"? v0.1.0: no. The
  conversation history covers this naturally; injecting our own
  meta-commentary risks confusion. Revisit if evals show repeated bad
  attempts on the same action.
- **Hint injection on repair:** if the action has a `hint` annotation,
  should we re-inject it on each repair feedback? v0.1.0: no, the hint is
  in the loaded skill detail. If it isn't loaded, the repair feedback
  doesn't help much anyway — but a model that has loaded the skill
  doesn't need the hint repeated.
