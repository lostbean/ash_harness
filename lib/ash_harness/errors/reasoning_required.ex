defmodule AshHarness.Errors.ReasoningRequired do
  @moduledoc """
  Returned when an action listed in the agent's `require_reasoning_for`
  is invoked without a non-empty `reasoning` argument. Splode class:
  `:reasoning`. Retryable — the LLM can re-issue the call with
  reasoning.
  """

  @type t :: %__MODULE__{
          agent: module() | nil,
          resource: module() | nil,
          action: atom() | nil
        }

  defexception [:agent, :resource, :action]

  @impl true
  def message(%__MODULE__{resource: resource, action: action}) do
    "reasoning required for #{inspect(resource)}.#{inspect(action)} " <>
      "(missing or empty `reasoning` argument)"
  end
end
