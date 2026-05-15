defmodule AshHarness.Harness.ReasoningGate do
  @moduledoc """
  Refuses a tool dispatch for an action listed in
  `require_reasoning_for` when the input does not include a non-empty
  `reasoning` string.

  Returns `{:error, %AshHarness.Errors.ReasoningRequired{}}` on refusal
  (v0.1.2 struct-error contract).
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Errors.ReasoningRequired
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, ReasoningRequired.t()}
  def check(
        %Session{agent: agent},
        %Intent{action: action, reasoning: reasoning} = intent
      ) do
    required? = AgentInfo.reasoning_required?(agent, action)
    present? = is_binary(reasoning) and byte_size(reasoning) > 0

    # v0.1.2: always emit `:checked` so pass-rate listeners see both
    # the required and present booleans regardless of the outcome.
    Telemetry.emit(
      [:ash_harness, :reasoning, :checked],
      %{required: required?, present: present?},
      %{
        agent: agent,
        resource: intent.resource,
        action: action,
        request_id: intent.request_id
      }
    )

    cond do
      not required? ->
        :ok

      present? ->
        :ok

      true ->
        Telemetry.emit(
          [:ash_harness, :reasoning, :missing],
          %{},
          %{
            agent: agent,
            resource: intent.resource,
            action: action,
            request_id: intent.request_id
          }
        )

        {:error,
         %ReasoningRequired{
           agent: agent,
           resource: intent.resource,
           action: action
         }}
    end
  end
end
