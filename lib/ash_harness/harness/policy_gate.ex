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
      result = can?(actor, intent)

      case result do
        false ->
          emit_checked(session.agent, intent, false)

          ash_error = %Ash.Error.Forbidden{}

          Telemetry.emit(
            [:ash_harness, :policy, :denied],
            %{},
            %{
              agent: session.agent,
              resource: intent.resource,
              action: intent.action,
              ash_error_class: ash_error_class(ash_error),
              request_id: intent.request_id
            }
          )

          {:error,
           %PolicyDenied{
             agent: session.agent,
             resource: intent.resource,
             action: intent.action,
             actor: actor,
             ash_error: ash_error
           }}

        _ ->
          emit_checked(session.agent, intent, true)
          :ok
      end
    else
      # Read actions short-circuit; the executor still runs Ash policies
      # on the read, but the gate trivially passes. Emit anyway so the
      # listener count matches the dispatch count.
      emit_checked(session.agent, intent, true)
      :ok
    end
  end

  # v0.1.2 `:checked` pass-event. Fires on every evaluation regardless
  # of whether the action was a read/mutation or whether the gate passed.
  defp emit_checked(agent, %Intent{} = intent, passed?) do
    Telemetry.emit(
      [:ash_harness, :policy, :checked],
      %{},
      %{
        agent: agent,
        resource: intent.resource,
        action: intent.action,
        passed: passed?,
        request_id: intent.request_id
      }
    )
  end

  # The Splode error class for the denial. For `:maybe` we fall back to
  # `:forbidden` because the gate refuses on `false` only; this helper
  # documents the explicit denial path.
  defp ash_error_class(%Ash.Error.Forbidden{class: class}) when not is_nil(class), do: class
  defp ash_error_class(%Ash.Error.Forbidden{}), do: :forbidden
  defp ash_error_class(_), do: :unknown

  defp can?(actor, %Intent{resource: resource, action: action_name, input: input}) do
    Ash.can?({resource, action_name, input || %{}}, actor)
  rescue
    _ -> :maybe
  end
end
