defmodule AshHarness.Resource.Hint do
  @moduledoc """
  Per-action agent-facing hint declared inside `agent_annotations`.

  Hints are short strings the LLM sees alongside the action's name and
  description in the rendered context. Use them to nudge the agent
  toward the right tool for a job.
  """

  defstruct [:action_name, :text, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          action_name: atom(),
          text: String.t(),
          __spark_metadata__: term() | nil
        }
end
