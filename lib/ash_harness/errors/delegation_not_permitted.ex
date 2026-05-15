defmodule AshHarness.Errors.DelegationNotPermitted do
  @moduledoc """
  Returned by `AshHarness.Delegation.initiate/4` when the calling
  agent's `delegates_to` does not list the target agent. Splode class:
  `:delegation`.
  """

  @type t :: %__MODULE__{
          from: module() | nil,
          to: module() | nil,
          reason: atom() | nil
        }

  defexception [:from, :to, :reason]

  @impl true
  def message(%__MODULE__{from: from, to: to}) do
    "delegation not permitted: #{inspect(from)} cannot delegate to #{inspect(to)}"
  end
end
