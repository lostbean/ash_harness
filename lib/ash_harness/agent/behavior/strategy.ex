defmodule AshHarness.Agent.Behavior.Strategy do
  @moduledoc """
  A named strategy hint shown in the agent's rendered context.
  """

  defstruct [:name, :description, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          __spark_metadata__: term() | nil
        }
end
