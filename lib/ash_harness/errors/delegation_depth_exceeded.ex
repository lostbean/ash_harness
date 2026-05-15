defmodule AshHarness.Errors.DelegationDepthExceeded do
  @moduledoc """
  Returned by `AshHarness.Delegation.initiate/4` when the delegation
  chain would exceed the configured `max_depth` (default 3). Splode
  class: `:delegation`.
  """

  @type t :: %__MODULE__{
          from: module() | nil,
          to: module() | nil,
          depth: non_neg_integer() | nil,
          max_depth: non_neg_integer() | nil
        }

  defexception [:from, :to, :depth, :max_depth]

  @impl true
  def message(%__MODULE__{from: from, to: to, depth: depth, max_depth: max_depth}) do
    "delegation depth exceeded: #{inspect(from)} -> #{inspect(to)} " <>
      "at depth #{inspect(depth)} (max #{inspect(max_depth)})"
  end
end
