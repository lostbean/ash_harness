defmodule AshHarness.Agent.Delegation.DelegateEntry do
  @moduledoc """
  An entry in the agent's `delegates_to` section: the target agent
  module, a short string alias the LLM uses to refer to the target,
  and a description of when this delegate should be used.

  The `:as` alias is the case-insensitive name the LLM passes to the
  `delegate(target, question)` skill.
  """

  defstruct [:agent_module, :as, :purpose, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          agent_module: module(),
          as: String.t() | nil,
          purpose: String.t(),
          __spark_metadata__: term() | nil
        }
end
