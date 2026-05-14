defmodule AshHarness.Agent.Delegation.DelegateEntry do
  @moduledoc """
  An entry in the agent's `delegates_to` section: the target agent
  module and a description of when this delegate should be used.
  """

  defstruct [:agent_module, :for, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          agent_module: module(),
          for: String.t(),
          __spark_metadata__: term() | nil
        }
end
