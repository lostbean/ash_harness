defmodule AshHarness.Harness.PolicyGate do
  @moduledoc """
  Calls `Ash.can?/2` before executing any mutating action. On `false`,
  refuses with `%AshHarness.Errors.PolicyDenied{}`; on `true` or
  `:maybe`, execution continues. Read actions are not policy-gated
  here — the executor passes the actor through to `Ash.read/2`, which
  applies Ash policies on the read.

  Returns `{:error, %AshHarness.Errors.PolicyDenied{}}` on refusal
  (v0.1.2 struct-error contract). The struct carries a synthetic
  `%Ash.Error.Forbidden{}` in `:ash_error` so the repair formatter
  can produce a consistent message regardless of whether the denial
  came from the gate or the executor.
  """

  alias AshHarness.Errors.PolicyDenied
  alias AshHarness.Harness.BudgetGate
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, PolicyDenied.t()}
  def check(%Session{actor: actor} = session, %Intent{} = intent) do
    if BudgetGate.mutating?(intent) do
      case can?(actor, intent) do
        false ->
          Telemetry.emit(
            [:ash_harness, :policy, :denied],
            %{},
            %{
              agent: session.agent,
              resource: intent.resource,
              action: intent.action,
              request_id: intent.request_id
            }
          )

          {:error,
           %PolicyDenied{
             agent: session.agent,
             resource: intent.resource,
             action: intent.action,
             actor: actor,
             ash_error: %Ash.Error.Forbidden{}
           }}

        _ ->
          :ok
      end
    else
      :ok
    end
  end

  defp can?(actor, %Intent{resource: resource, action: action_name, input: input}) do
    Ash.can?({resource, action_name, input || %{}}, actor)
  rescue
    _ -> :maybe
  end
end
