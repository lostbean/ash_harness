defmodule AshHarness.Harness.Session do
  @moduledoc """
  Per-conversation state for a running agent. Built by
  `AshHarness.Harness.new_session/2`; carries the actor, the rendered
  context, the underlying Jido agent (orchestrator state), the
  trajectory, the per-turn mutation budget counter, and host-app
  metadata.
  """

  defstruct [
    :agent,
    :actor,
    :model,
    :rendered_context,
    :jido_orchestrator,
    :request_id,
    trajectory: [],
    mutation_count: 0,
    turn_number: 0,
    metadata: %{},
    loaded_skills: MapSet.new(),
    repair_attempts: %{},
    options: []
  ]

  @type trajectory_entry :: %AshHarness.Harness.TrajectoryEntry{}
  @type t :: %__MODULE__{
          agent: module(),
          actor: any(),
          model: String.t() | nil,
          rendered_context: AshHarness.RenderedContext.t() | nil,
          jido_orchestrator: term() | nil,
          request_id: String.t() | nil,
          trajectory: [trajectory_entry()],
          mutation_count: non_neg_integer(),
          turn_number: non_neg_integer(),
          metadata: map(),
          loaded_skills: MapSet.t(),
          repair_attempts: %{optional({module(), atom()}) => non_neg_integer()},
          options: keyword()
        }
end
