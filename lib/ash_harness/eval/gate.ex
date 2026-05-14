defmodule AshHarness.Eval.Gate do
  @moduledoc """
  A pass/fail gate in a scenario. `kind` is `:resource_state` or
  `:invariant`; `check` is a 1-arity function that receives the
  scenario context (setup result + final session) and returns a list
  of `{label, passed?, observation}` tuples.
  """

  defstruct [:kind, :check]

  @type kind :: :resource_state | :invariant
  @type check_result :: [{atom() | String.t(), boolean(), term()}]
  @type t :: %__MODULE__{
          kind: kind(),
          check: (map() -> check_result())
        }
end
