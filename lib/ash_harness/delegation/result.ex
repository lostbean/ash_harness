defmodule AshHarness.Delegation.Result do
  @moduledoc """
  Internal struct shared between `AshHarness.Delegation.Initiate` and
  the telemetry/trajectory writers so the four fields of a delegation
  outcome — the reply text, the target trajectory id, the target's
  trajectory snapshot, and the run status — flow as one value rather
  than four ad-hoc locals.

  Not part of the public API; the public `Delegation.initiate/4` still
  returns the historical
  `{:ok, reply, updated_session, target_trajectory}` tuple shape.
  """

  alias AshHarness.Harness.TrajectoryEntry

  defstruct [:reply_text, :target_trajectory_id, :target_trajectory, :status]

  @type status :: :ok | :error | :halt

  @type t :: %__MODULE__{
          reply_text: String.t(),
          target_trajectory_id: String.t(),
          target_trajectory: [TrajectoryEntry.t()],
          status: status()
        }
end
