defmodule AshHarness.Eval.Result do
  @moduledoc """
  The outcome of running one scenario. `:passed` is `true` iff every
  gate's checks returned `true`. There is intentionally no
  `composite_score` field — pass/fail is determined solely by gates
  (see ADR 0002).
  """

  defstruct [
    :scenario_name,
    :passed,
    :gate_results,
    :report_results,
    :duration_ms,
    :tokens_used,
    :session_trajectory,
    :terminated_reason,
    :terminated_error
  ]

  @type terminated_reason ::
          :goal_met | :max_turns | :error | :not_executed | nil

  @type t :: %__MODULE__{
          scenario_name: String.t(),
          passed: boolean(),
          gate_results: [map()],
          report_results: [map()],
          duration_ms: non_neg_integer() | nil,
          tokens_used: non_neg_integer() | nil,
          session_trajectory: list(),
          terminated_reason: terminated_reason(),
          terminated_error: term() | nil
        }
end
