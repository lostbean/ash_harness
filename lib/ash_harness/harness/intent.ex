defmodule AshHarness.Harness.Intent do
  @moduledoc """
  Declaration of what a tool call wants to do. Constructed inside the
  generated Jido.Action's `run/2` before any gate runs.
  """

  defstruct [
    :resource,
    :action,
    :input,
    :reasoning,
    :request_id,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          resource: module(),
          action: atom(),
          input: map(),
          reasoning: String.t() | nil,
          request_id: String.t() | nil,
          metadata: map()
        }
end
