defmodule AshHarness.Agent.Identity do
  @moduledoc """
  The agent's identity card: a name, a description, an actor (struct,
  0-arity function, or MFA tuple), and an optional model string.
  """

  defstruct [:name, :description, :actor, :model, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          actor: any(),
          model: String.t() | nil,
          __spark_metadata__: term() | nil
        }
end
