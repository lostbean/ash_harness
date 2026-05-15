defmodule AshHarness.Errors.MutationLimitExceeded do
  @moduledoc """
  Returned when the session's per-turn mutation budget is exhausted
  and another mutating action is attempted. Splode class: `:budget`.
  """

  @type t :: %__MODULE__{
          agent: module() | nil,
          count: non_neg_integer() | nil,
          max: non_neg_integer() | nil
        }

  defexception [:agent, :count, :max]

  @impl true
  def message(%__MODULE__{agent: agent, count: count, max: max}) do
    "mutation budget exhausted for #{inspect(agent)}: " <>
      "#{inspect(count)} of #{inspect(max)} mutations used this turn"
  end
end
