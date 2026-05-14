defmodule AshHarness.Eval.RunnerTerminatedReasonTest do
  @moduledoc """
  Verifies that `AshHarness.Eval.Result.terminated_reason` is an atom
  from the spec'd enum (`:goal_met | :max_turns | :error | :not_executed
  | nil`) and that the underlying error reason (when applicable) lands
  on a separate `:terminated_error` field.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Eval.Runner
  alias AshHarness.Test.TriageAgent

  describe "terminated_reason is an atom from the spec enum" do
    test ":not_executed for scenarios with no agent" do
      defmodule NoAgentEval do
        use AshHarness.Eval

        scenario "no-agent" do
          agent(nil)
          prompt("hi")

          gate :invariant do
            true
          end
        end
      end

      [scenario] = NoAgentEval.scenarios()
      result = Runner.run(scenario)
      assert result.terminated_reason == :not_executed
      assert result.terminated_error == nil
    end

    test ":error when the runner's drive_agent raises (missing cassette in replay mode)" do
      # Ensure cassette mode is :replay (default). A scenario whose
      # cassette doesn't exist will cause ReqCassette to raise inside
      # drive_agent. The runner must capture that as terminated_reason:
      # :error (an atom), with the underlying exception on
      # terminated_error.
      System.delete_env("ASH_HARNESS_CASSETTE_MODE")

      defmodule ReplayMissEval do
        use AshHarness.Eval

        scenario "replay-miss" do
          agent(TriageAgent)
          prompt("Do something.")

          gate :invariant do
            true
          end
        end
      end

      [scenario] = ReplayMissEval.scenarios()
      result = Runner.run(scenario)

      assert result.terminated_reason == :error,
             "expected :error atom, got: #{inspect(result.terminated_reason)}"

      assert result.terminated_error != nil,
             "expected the underlying error to be captured on :terminated_error"
    end
  end

  describe "Result struct typespec surface" do
    test "result struct exposes terminated_error field" do
      defmodule TerminatedErrorFieldEval do
        use AshHarness.Eval

        scenario "field-exists" do
          agent(nil)
          prompt("hi")

          gate :invariant do
            true
          end
        end
      end

      [scenario] = TerminatedErrorFieldEval.scenarios()
      result = Runner.run(scenario)
      assert Map.has_key?(result, :terminated_error)
    end
  end
end
