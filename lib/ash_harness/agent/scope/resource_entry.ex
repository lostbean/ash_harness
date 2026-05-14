defmodule AshHarness.Agent.Scope.ResourceEntry do
  @moduledoc """
  An entry in the agent's `scope` section: a resource module and the
  list of action atoms the agent is allowed to invoke on it.
  """

  defstruct [:module, actions: [], __spark_metadata__: nil]

  @type t :: %__MODULE__{
          module: module(),
          actions: [atom()],
          __spark_metadata__: term() | nil
        }
end
