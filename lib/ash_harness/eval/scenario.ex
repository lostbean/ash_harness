defmodule AshHarness.Eval.Scenario do
  @moduledoc """
  One scenario in an `AshHarness.Eval` module. Built by the
  `scenario "..." do ... end` macro and consumed by
  `AshHarness.Eval.Runner.run/2`.
  """

  defstruct [
    :name,
    :agent,
    :setup,
    :prompt,
    :auto_confirm,
    gates: [],
    reports: []
  ]

  @type auto_confirm_mode ::
          :always_approve
          | :always_reject
          | {:custom, (term() -> :approved | :rejected)}
          | nil

  @type t :: %__MODULE__{
          name: String.t(),
          agent: module() | nil,
          setup: (-> map()) | nil,
          prompt: String.t() | nil,
          auto_confirm: auto_confirm_mode(),
          gates: [AshHarness.Eval.Gate.t()],
          reports: [AshHarness.Eval.Report.t()]
        }
end
