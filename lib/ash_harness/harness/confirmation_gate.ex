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
    if AgentInfo.confirms_action?(agent, intent.action) do
      case approval_entry(session, intent) do
        nil ->
          emit_requested(agent, intent)

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

          {:halt, request}

        entry ->
          # v0.1.2: surface `respondent` + `duration_ms` from the
          # stored approval entry. Falls back gracefully when the
          # legacy bare-atom shape (`:approved`) is encountered.
          Telemetry.emit(
            [:ash_harness, :confirmation, :approved],
            %{duration_ms: duration_ms(entry)},
            %{
              agent: agent,
              resource: intent.resource,
              action: intent.action,
              respondent: respondent(entry),
              request_id: intent.request_id
            }
          )

          :ok
      end
    else
      :ok
    end
  end

  defp emit_requested(agent, %Intent{} = intent) do
    Telemetry.emit(
      [:ash_harness, :confirmation, :requested],
      %{},
      %{
        agent: agent,
        resource: intent.resource,
        action: intent.action,
        request_id: intent.request_id
      }
    )
  end

  # Returns the recorded approval entry for the action under request,
  # or `nil` when no approval is on file. Entry is either a bare atom
  # decision (legacy `:approved`/`:rejected`) or a map with
  # `:decision`, `:respondent`, `:duration_ms`.
  defp approval_entry(%Session{metadata: meta}, %Intent{} = intent) do
    case Map.get(meta || %{}, :approvals, %{}) do
      %{} = approvals -> Map.get(approvals, {intent.resource, intent.action})
      _ -> nil
    end
  end

  defp respondent(%{respondent: r}), do: r
  defp respondent(_), do: :unspecified

  defp duration_ms(%{duration_ms: d}) when is_integer(d), do: d
  defp duration_ms(_), do: 0
end
