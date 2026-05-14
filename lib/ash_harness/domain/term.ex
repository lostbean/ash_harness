defmodule AshHarness.Domain.Term do
  @moduledoc """
  A domain-vocabulary entry: one word, one definition. Declared inside
  the `agent_domain` section of a domain that uses
  `AshHarness.Domain`.
  """

  defstruct [:word, :definition, __spark_metadata__: nil]

  @type t :: %__MODULE__{
          word: String.t(),
          definition: String.t(),
          __spark_metadata__: term() | nil
        }
end
