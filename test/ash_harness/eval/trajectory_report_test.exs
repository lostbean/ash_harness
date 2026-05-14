defmodule AshHarness.Eval.TrajectoryReportTest do
  use ExUnit.Case, async: true

  alias AshHarness.Eval.Runner

  defmodule MaxTokensEval do
    use AshHarness.Eval

    scenario "under limit" do
      agent(nil)
      prompt("trivial")

      gate :invariant do
        true
      end

      report :trajectory do
        max_tokens(100)
      end
    end
  end

  defmodule IncludesSequenceEval do
    use AshHarness.Eval

    scenario "trajectory order" do
      agent(nil)
      prompt("trivial")

      gate :invariant do
        true
      end

      report :trajectory do
        includes_sequence([:ticket_read, :ticket_assign])
      end
    end
  end

  defmodule ExcludesEval do
    use AshHarness.Eval

    scenario "trajectory exclusion" do
      agent(nil)
      prompt("trivial")

      gate :invariant do
        true
      end

      report :trajectory do
        excludes([:ticket_destroy])
      end
    end
  end

  describe "max_tokens" do
    test "ok when tokens_used <= max" do
      [scenario] = MaxTokensEval.scenarios()
      result = Runner.run(scenario)
      [report] = result.report_results
      assert report.kind == :trajectory
      assert report.max_tokens == 100
      assert report.max_tokens_ok == true
    end
  end

  describe "includes_sequence" do
    test "missing sequence is reported as not_ok" do
      [scenario] = IncludesSequenceEval.scenarios()
      result = Runner.run(scenario)
      [report] = result.report_results
      # No agent ran, so trajectory is empty; the sequence isn't satisfied
      assert report.includes_sequence == [:ticket_read, :ticket_assign]
      assert report.includes_sequence_ok == false
    end
  end

  describe "excludes" do
    test "ok when no excluded action present" do
      [scenario] = ExcludesEval.scenarios()
      result = Runner.run(scenario)
      [report] = result.report_results
      assert report.excludes == [:ticket_destroy]
      # empty trajectory contains nothing
      assert report.excludes_ok == true
    end
  end
end
