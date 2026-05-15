defmodule AshHarness.Errors.ScopeViolation do
  @moduledoc """
  Raised (or returned wrapped in `{:error, _}`) when an LLM tool call
  targets a `(resource, action)` pair that is not in the agent's
  declared scope. Splode class: `:scope`.
  """

  @type t :: %__MODULE__{
          agent: module() | nil,
          resource: module() | nil,
          action: atom() | nil
        }

  defexception [:agent, :resource, :action]

  @impl true
  def message(%__MODULE__{agent: agent, resource: resource, action: action}) do
    "scope violation: #{inspect(agent)} cannot invoke " <>
      "#{inspect(resource)}.#{inspect(action)} (not in scope)"
  end
end
