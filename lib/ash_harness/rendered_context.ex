defmodule AshHarness.RenderedContext do
  @moduledoc """
  Output of `AshHarness.ContextRenderer.render/2`. Holds the agent's
  initial system-prompt text plus a per-resource detail map for
  on-demand loading via the `load_resource_skill` meta-tool, plus the
  estimated token count and any warnings the renderer produced.
  """

  defstruct [
    :initial_text,
    :token_estimate,
    resource_details: %{},
    warnings: []
  ]

  @type t :: %__MODULE__{
          initial_text: String.t(),
          token_estimate: non_neg_integer(),
          resource_details: %{atom() => String.t()},
          warnings: [String.t()]
        }
end
