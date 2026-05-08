# Layer 07 — Harness Runtime

The runtime layer that mediates between Jido orchestrators and Ash. Owns
the gate pipeline, the trajectory log, and the action executor.

## Public API

```elixir
defmodule AshHarness.Harness do
  @type session :: AshHarness.Harness.Session.t()

  @spec new_session(module(), keyword()) :: session()
  # Resolves the actor; renders initial context; assembles a Jido orchestrator.
  # Opts:
  #   :actor — overrides identity.actor for this session
  #   :model — overrides identity.model
  #   :extra_tools — list of dynamic tools (AshHarness.Tool.dynamic/2)
  #   :metadata — opaque map carried in trajectory entries
  def new_session(agent_module, opts \\ [])

  @spec run(session(), String.t(), keyword()) ::
    {:ok, assistant_reply :: String.t(), session()}
    | {:halt, %Jido.Composer.HITL.ApprovalRequest{}, session()}
    | {:error, term(), session()}
  # Sends user_message to the orchestrator, runs the loop until terminal,
  # returns the reply, the suspension request, or an error.
  def run(session, user_message, opts \\ [])

  @spec resume(session(), %Jido.Composer.HITL.ApprovalResponse{}) ::
    {:ok, assistant_reply :: String.t(), session()}
    | {:halt, %Jido.Composer.HITL.ApprovalRequest{}, session()}
    | {:error, term(), session()}
  # Resumes after a HITL approval/rejection.
  def resume(session, approval_response)

  @spec trajectory(session()) :: [AshHarness.Harness.TrajectoryEntry.t()]
  def trajectory(session)

  @spec mutation_count(session()) :: non_neg_integer()
  def mutation_count(session)
end
```

The shape returns `{:ok | :halt | :error, _, session}` so callers can
chain. The session struct accumulates trajectory and mutation count
across `run`/`resume` calls.

## Session struct

```elixir
defmodule AshHarness.Harness.Session do
  defstruct [
    :agent,                # module
    :actor,                # resolved actor
    :model,                # resolved model string
    :rendered_context,     # %RenderedContext{}
    :jido_orchestrator,    # %Jido.Composer.Orchestrator.State{}
    :trajectory,           # [TrajectoryEntry.t()]
    :mutation_count,       # non_neg_integer
    :turn_number,          # non_neg_integer
    :metadata,             # opaque
    :request_id,           # binary
    :loaded_skills,        # MapSet of resource modules whose detail is loaded
    :options
  ]
end
```

## Intent struct

```elixir
defmodule AshHarness.Harness.Intent do
  defstruct [:resource, :action, :input, :reasoning, :request_id]
end
```

The model never constructs an Intent directly. The Intent is built inside
the generated Jido.Action's `run/2` from the (resource, action) bound at
generation time and the `input` arg.

## Result struct

```elixir
defmodule AshHarness.Harness.Result do
  @type status :: :ok | :error | :scope_violation | :reasoning_required
                | :confirmation_required | :budget_exceeded | :policy_denied

  defstruct [:status, :intent, :data, :error, :changeset_errors, :duration_ms]
end
```

## Trajectory entry

```elixir
defmodule AshHarness.Harness.TrajectoryEntry do
  defstruct [
    :timestamp,           # DateTime
    :turn_number,
    :intent,              # the original intent
    :result_status,
    :duration_ms,
    :tokens_used,         # estimated for this step
    :repair_attempts,     # int — how many repair-loop attempts on this intent
    :metadata
  ]
end
```

## The gate pipeline

For each tool call from the orchestrator, the generated Jido.Action's
`run/2` invokes
`AshHarness.Harness.GeneratedAction.dispatch/5`, which runs:

```text
1. Build %Intent{} from (resource, action, input, ctx)
2. ScopeGate.check(session, intent)
   ─ if not in scope → emit :scope_violation telemetry; return error
3. ReasoningGate.check(session, intent)
   ─ if intent.action ∈ require_reasoning_for and intent.reasoning is nil
     → emit :reasoning_missing telemetry; return error
4. ConfirmationGate.check(session, intent)
   ─ if intent.action ∈ confirm_before and not previously approved
     → halt with %ApprovalRequest{};
       host app surfaces it; on response, resume re-enters at step 5
5. BudgetGate.check(session, intent)
   ─ if intent.action is mutating and session.mutation_count == max
     → return error
6. PolicyGate.check(session, intent)
   ─ Ash.can?(actor, action_input) → false → return :policy_denied error
7. ActionExecutor.run(session.actor, intent)
   ─ dispatches Ash.read | Ash.create | Ash.update | Ash.destroy | Ash.run_action
   ─ on success: mutating action increments mutation_count
   ─ on validation error: pass to Repair.format_feedback
8. TrajectoryAppend
9. Telemetry emit
10. Return {:ok, rendered_result} | {:error, formatted_text}
```

Each gate is a separate module so it can be unit-tested in isolation
without spinning up Jido or Ash.

## Action executor

```elixir
defmodule AshHarness.Harness.ActionExecutor do
  @spec run(actor :: any(), %Intent{}) ::
    {:ok, any()} | {:error, term()}
  def run(actor, intent) do
    action_def = Ash.Resource.Info.action(intent.resource, intent.action)

    case action_def.type do
      :read ->
        Ash.read(intent.resource, action: intent.action, actor: actor,
                 input: intent.input)

      :create ->
        Ash.create(intent.resource, action: intent.action, actor: actor,
                   input: intent.input)

      :update ->
        with {:ok, record} <- load_record(intent, actor) do
          Ash.update(record, action: intent.action, actor: actor,
                     input: Map.delete(intent.input, :id))
        end

      :destroy ->
        with {:ok, record} <- load_record(intent, actor) do
          Ash.destroy(record, action: intent.action, actor: actor,
                      input: Map.delete(intent.input, :id))
        end

      :action ->  # generic
        Ash.run_action(intent.resource, intent.action, intent.input, actor: actor)
    end
    |> wrap_result()
  end

  defp wrap_result({:ok, _} = ok), do: ok
  defp wrap_result({:error, %Ash.Error.Forbidden{} = e}),
    do: {:error, {:policy_denied, e}}
  defp wrap_result({:error, %Ash.Error.Invalid{} = e}),
    do: {:error, {:validation_failed, e}}
  defp wrap_result({:error, e}), do: {:error, e}
end
```

Update/destroy actions require an `id` in the input — we load the record
first so Ash policies that depend on the existing record can be
evaluated.

## Result rendering

What the LLM sees as the tool_result depends on the action type:

| Action type | Result rendering |
| --- | --- |
| `:read` (list) | First N records as JSON, plus a count and pagination cursor. N = config (default 50). |
| `:read` (single, e.g. `get`) | One record as JSON. |
| `:create` | Created record as JSON. |
| `:update` | Updated record as JSON, with a `_changed_fields` summary. |
| `:destroy` | `{"destroyed": true, "id": "…"}`. |
| `:action` (generic) | Whatever the action returns; cast to JSON. |

`hidden_attributes` are excluded from rendered records.

## Confirmation flow

When `ConfirmationGate` triggers, it returns `{:halt, request}` from
the Jido.Action. Jido suspends the orchestrator and emits a
`%Jido.Composer.HITL.ApprovalRequest{}` to the host. The shape:

```elixir
%Jido.Composer.HITL.ApprovalRequest{
  id: "req_…",
  prompt: "Approve action ticket__assign?",
  metadata: %{
    intent: %{resource: "Ticket", action: :assign, input: %{...}, reasoning: "..."},
    agent: "MyAgent"
  },
  allowed_responses: [:approved, :rejected]
}
```

The host app presents this to a user and calls
`AshHarness.Harness.resume(session, response)` with:

```elixir
%Jido.Composer.HITL.ApprovalResponse{
  id: "req_…",
  decision: :approved | :rejected,
  respondent: "user@example.com",
  metadata: %{}
}
```

On `:approved`, the gate is satisfied and execution continues at
`BudgetGate`. On `:rejected`, the gate returns
`{:error, "user denied this action"}`, which the orchestrator feeds to
the LLM as the tool result.

## Repair loop integration

When `ActionExecutor.run/2` returns `{:error, {:validation_failed,
ash_error}}`, the dispatch wraps it with `Repair.format_feedback/1` to
produce a human-readable string. The LLM sees that string as the tool
result and may issue a corrected call on the next turn.

The harness tracks repair attempts per intent (same `tool_use_id`
loosely, but in practice we count per-(resource, action) within a turn).
If repair attempts exceed `max_repair_loop_retries`, the dispatch
returns an error indicating "stop retrying."

## Mutation count

Incremented only on successful create / update / destroy / mutating
generic actions. Reads do not count. The count is **per session**, not
per turn, despite the constraint name `max_mutations_per_turn` — we
treat "turn" as "the current `run/2`/`resume/2` call." This is
defensible (and how Jido sees turns), and matches what users expect.

If we need a session-level cap separately, add `max_mutations_total` to
constraints in v0.2.

## Hot reload

In dev, when an agent module is recompiled, its generated tool modules
are also recompiled. The session's stored orchestrator may reference
stale modules. We don't auto-detect this — it's a dev-time concern.
Users restart the IEx node or call `new_session/2` to refresh.

## Open questions

- **Should `run/2` be sync-only?** v0.1.0: yes, sync. The host owns
  async dispatch (e.g., from a LiveView assign).
- **Should we expose a streaming variant?** Defer to v0.2 — Jido streaming
  is supported, but threading it through the gate pipeline needs care.
- **Per-tenant orchestrator caching?** Out of scope for v0.1.0; build a
  fresh orchestrator per session (cheap).
