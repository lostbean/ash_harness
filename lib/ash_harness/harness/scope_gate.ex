defmodule AshHarness.Harness.ScopeGate do
  @moduledoc """
  Refuses any tool dispatch whose (resource, action) pair isn't in
  the agent's declared scope.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, :scope_violation}
  def check(
        %Session{agent: agent} = session,
        %Intent{resource: resource, action: action} = intent
      ) do
    if AgentInfo.in_scope?(agent, resource, action) do
      :ok
    else
      Telemetry.emit(
        [:ash_harness, :scope, :violation],
        %{},
        %{
          agent: agent,
          resource: resource,
          action: action,
          request_id: session.request_id || intent.request_id
        }
      )

      {:error, :scope_violation}
    end
  end
end
