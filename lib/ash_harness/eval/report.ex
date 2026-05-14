defmodule AshHarness.Eval.Report do
  @moduledoc """
  A diagnostic report on a scenario run. Two kinds: `:trajectory`
  (with `max_actions`, `max_tokens`, `includes_sequence`, `excludes`)
  and `:qualitative` (LLM-as-judge).

  Reports never affect `result.passed`; they appear in
  `result.report_results` for inspection.
  """

  defstruct [:kind, :compute]

  @type kind :: :trajectory | :qualitative
  @type t :: %__MODULE__{
          kind: kind(),
          compute: (map() -> map())
        }
end
