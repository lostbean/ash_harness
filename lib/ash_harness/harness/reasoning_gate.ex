defmodule AshHarness.Harness.ReasoningGate do
  @moduledoc """
  Refuses a tool dispatch for an action listed in
  `require_reasoning_for` when the input does not include a non-empty
  `reasoning` string.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, :reasoning_required}
  def check(
        %Session{agent: agent} = session,
        %Intent{action: action, reasoning: reasoning} = intent
      ) do
    cond do
      not AgentInfo.reasoning_required?(agent, action) ->
        :ok

      is_binary(reasoning) and byte_size(reasoning) > 0 ->
        :ok

      true ->
        Telemetry.emit(
          [:ash_harness, :reasoning, :missing],
          %{},
          %{
            agent: agent,
            resource: intent.resource,
            action: action,
            request_id: session.request_id || intent.request_id
          }
        )

        {:error, :reasoning_required}
    end
  end
end
