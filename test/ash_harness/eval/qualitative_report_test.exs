defmodule AshHarness.Eval.QualitativeReportTest do
  use ExUnit.Case, async: false

  alias AshHarness.Eval.Runner
  alias AshHarness.Test.LLMStub

  defmodule NoJudgeEval do
    use AshHarness.Eval

    scenario "no judge configured" do
      agent(nil)
      prompt("trivial")

      gate :invariant do
        true
      end

      report :qualitative do
        criterion(:concise, threshold: 0.7, prompt: "Was the response concise?")
      end
    end
  end

  defmodule WithJudgeEval do
    use AshHarness.Eval

    scenario "judge scores criteria" do
      agent(nil)
      prompt("trivial")

      gate :invariant do
        true
      end

      report :qualitative do
        criterion(:concise, threshold: 0.7, prompt: "Was the response concise?")
        criterion(:accurate, threshold: 0.5, prompt: "Was it accurate?")
      end
    end
  end

  describe "without judge_model configured" do
    test "returns empty scores map, doesn't fail" do
      [scenario] = NoJudgeEval.scenarios()
      result = Runner.run(scenario)
      [report] = result.report_results
      assert report.kind == :qualitative
      assert report.scores == %{}
      # The scenario passes because the gate is invariant true
      assert result.passed
    end
  end

  describe "with judge_model + stub plug" do
    test "scores each criterion from the judge response" do
      judge_pid =
        LLMStub.start_link!([
          # Judge returns JSON in a text block
          LLMStub.text(~s({"concise": 0.9, "accurate": 0.6}))
        ])

      [scenario] = WithJudgeEval.scenarios()

      result =
        Runner.run(scenario,
          judge_model: "anthropic:claude-sonnet-4-5",
          judge_req_options: [plug: {LLMStub, judge_pid}]
        )

      [report] = result.report_results
      assert report.kind == :qualitative
      assert report.scores[:concise] == 0.9
      assert report.scores[:accurate] == 0.6

      # Concise: 0.9 >= 0.7 (passes); accurate: 0.6 >= 0.5 (passes)
      below = Enum.filter(report.observations, fn o -> o.below_threshold? end)
      assert below == []
    end

    test "below-threshold scores are flagged in observations" do
      judge_pid =
        LLMStub.start_link!([
          LLMStub.text(~s({"concise": 0.5, "accurate": 0.4}))
        ])

      [scenario] = WithJudgeEval.scenarios()

      result =
        Runner.run(scenario,
          judge_model: "anthropic:claude-sonnet-4-5",
          judge_req_options: [plug: {LLMStub, judge_pid}]
        )

      [report] = result.report_results
      assert report.scores[:concise] == 0.5
      assert report.scores[:accurate] == 0.4

      names_below =
        report.observations
        |> Enum.filter(& &1.below_threshold?)
        |> Enum.map(& &1.name)

      assert :concise in names_below
      assert :accurate in names_below

      # Scenario.passed is gate-only — invariant true, so passes despite below-threshold
      assert result.passed
    end
  end
end
