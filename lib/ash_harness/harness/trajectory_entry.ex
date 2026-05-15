defmodule AshHarness.Harness.TrajectoryEntry do
  @moduledoc """
  One entry in a session's trajectory. Appended after every gate
  outcome and every action execution.
  """

  defstruct [
    :timestamp,
    :turn_number,
    :intent,
    :result_status,
    :duration_ms,
    :tokens_used,
    :repair_attempts,
    metadata: %{},
    data: %{}
  ]

  @type t :: %__MODULE__{
          timestamp: DateTime.t(),
          turn_number: non_neg_integer(),
          intent: AshHarness.Harness.Intent.t() | map(),
          result_status: atom(),
          duration_ms: non_neg_integer() | nil,
          tokens_used: non_neg_integer() | nil,
          repair_attempts: non_neg_integer() | nil,
          metadata: map(),
          data: map()
        }
end
