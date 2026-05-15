defmodule AshHarness.Harness.ScopeGate do
  @moduledoc """
  Refuses any tool dispatch whose (resource, action) pair isn't in
  the agent's declared scope.

  Returns `{:error, %AshHarness.Errors.ScopeViolation{}}` on refusal
  (v0.1.2 struct-error contract).
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Errors.ScopeViolation
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, ScopeViolation.t()}
  def check(
        %Session{agent: agent},
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
          request_id: intent.request_id
        }
      )

      {:error, %ScopeViolation{agent: agent, resource: resource, action: action}}
    end
  end
end
