defmodule AshHarness.Harness.ConfirmationGate do
  @moduledoc """
  Surfaces a confirmation request when the action is in
  `confirm_before` and no approval is present in the session metadata.

  Primary HITL halts in v0.1.0 are produced by the orchestrator
  strategy (configure `confirm_before` tool nodes with
  `requires_approval: true`). This gate is the secondary, defensive
  check that runs inside `GeneratedAction.dispatch/5` to ensure no
  unapproved confirm_before tool slips through if the orchestrator
  wasn't wired up.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry
  alias Jido.Composer.HITL.ApprovalRequest

  @spec check(Session.t(), Intent.t()) ::
          :ok | {:halt, ApprovalRequest.t()}
  def check(%Session{agent: agent} = session, %Intent{} = intent) do
    cond do
      not AgentInfo.confirms_action?(agent, intent.action) ->
        :ok

      approval_recorded?(session, intent) ->
        Telemetry.emit(
          [:ash_harness, :confirmation, :approved],
          %{},
          %{
            agent: agent,
            resource: intent.resource,
            action: intent.action,
            request_id: session.request_id || intent.request_id
          }
        )

        :ok

      true ->
        {:ok, request} =
          ApprovalRequest.new(
            prompt:
              "Agent #{inspect(agent)} requests approval to invoke " <>
                "#{inspect(intent.resource)}.#{intent.action}.",
            allowed_responses: [:approved, :rejected],
            metadata: %{
              agent: inspect(agent),
              resource: inspect(intent.resource),
              action: intent.action,
              input: intent.input,
              reasoning: intent.reasoning
            }
          )

        Telemetry.emit(
          [:ash_harness, :confirmation, :requested],
          %{},
          %{
            agent: agent,
            resource: intent.resource,
            action: intent.action,
            request_id: session.request_id || intent.request_id
          }
        )

        {:halt, request}
    end
  end

  defp approval_recorded?(%Session{metadata: meta}, %Intent{} = intent) do
    case Map.get(meta, :approvals, %{}) do
      %{} = approvals ->
        Map.has_key?(approvals, {intent.resource, intent.action})

      _ ->
        false
    end
  end
end
