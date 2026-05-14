defmodule AshHarness.Harness.PolicyGate do
  @moduledoc """
  Calls `Ash.can?/2` before executing any mutating action. On `false`,
  refuses with `:policy_denied`; on `true` or `:maybe`, execution
  continues. Read actions are not policy-gated here — the executor
  passes the actor through to `Ash.read/2`, which applies Ash policies
  on the read.
  """

  alias AshHarness.Harness.BudgetGate
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, :policy_denied}
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
              request_id: session.request_id || intent.request_id
            }
          )

          {:error, :policy_denied}

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
