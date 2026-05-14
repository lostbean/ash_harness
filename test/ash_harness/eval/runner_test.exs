defmodule AshHarness.Eval.RunnerTest do
  use ExUnit.Case, async: false

  alias AshHarness.Eval.Runner
  alias AshHarness.Test.FixturesEval

  test "module exposes scenarios/0" do
    assert length(FixturesEval.scenarios()) == 3
  end

  test "run/2 on passing scenario marks passed: true" do
    [scenario | _] = FixturesEval.scenarios()
    result = Runner.run(scenario)
    assert result.passed
    assert result.scenario_name == "always-passing gate"
  end

  test "run/2 on failing scenario marks passed: false" do
    scenario = Enum.at(FixturesEval.scenarios(), 1)
    result = Runner.run(scenario)
    refute result.passed
  end

  test "invariant gate passes when block is truthy" do
    scenario = Enum.at(FixturesEval.scenarios(), 2)
    result = Runner.run(scenario)
    assert result.passed
  end

  test "result struct has no composite_score field" do
    [scenario | _] = FixturesEval.scenarios()
    result = Runner.run(scenario)
    refute Map.has_key?(result, :composite_score)
  end

  test "run_all/2 returns one result per scenario" do
    results = Runner.run_all(FixturesEval)
    assert length(results) == 3
  end

  test "report results appear regardless of gate outcome" do
    [scenario | _] = FixturesEval.scenarios()
    result = Runner.run(scenario)
    assert length(result.report_results) == 1
    assert hd(result.report_results).kind == :trajectory
  end
end
