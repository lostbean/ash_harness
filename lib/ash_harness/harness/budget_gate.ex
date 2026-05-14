defmodule AshHarness.Harness.BudgetGate do
  @moduledoc """
  Refuses a mutating tool dispatch when the session's `mutation_count`
  has already reached the agent's `max_mutations_per_turn`. Reads do
  not increment the counter; failed mutations don't either. The
  counter is bumped only after a successful mutation (see
  `AshHarness.Harness.dispatch/5`).
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry

  @mutating_types ~w(create update destroy)a

  @spec check(Session.t(), Intent.t()) :: :ok | {:error, :budget_exceeded}
  def check(%Session{agent: agent, mutation_count: count} = session, %Intent{} = intent) do
    if mutating?(intent) and count >= AgentInfo.max_mutations_per_turn(agent) do
      Telemetry.emit(
        [:ash_harness, :budget, :exceeded],
        %{count: count, max: AgentInfo.max_mutations_per_turn(agent)},
        %{
          agent: agent,
          resource: intent.resource,
          action: intent.action,
          request_id: session.request_id || intent.request_id
        }
      )

      {:error, :budget_exceeded}
    else
      :ok
    end
  end

  @doc """
  Returns `true` when the intent corresponds to a mutating action.
  Used by both the gate and the post-execution counter bump.
  """
  @spec mutating?(Intent.t()) :: boolean()
  def mutating?(%Intent{resource: resource, action: action_name}) do
    case Ash.Resource.Info.action(resource, action_name) do
      %{type: type} when type in @mutating_types -> true
      _ -> false
    end
  end
end
