defmodule AshHarness.Eval.AutoConfirmTest do
  use ExUnit.Case, async: true

  alias AshHarness.Eval.Runner
  alias AshHarness.Eval.Scenario

  describe "Scenario.auto_confirm field" do
    test "is nil by default" do
      defmodule SampleEval do
        use AshHarness.Eval

        scenario "no override" do
          agent(nil)
          prompt("hi")

          gate :invariant do
            true
          end
        end
      end

      [scenario] = SampleEval.scenarios()
      assert is_nil(scenario.auto_confirm)
    end

    test "captures :always_reject when set" do
      defmodule RejectingEval do
        use AshHarness.Eval

        scenario "reject all" do
          agent(nil)
          prompt("hi")
          auto_confirm(:always_reject)

          gate :invariant do
            true
          end
        end
      end

      [scenario] = RejectingEval.scenarios()
      assert scenario.auto_confirm == :always_reject
    end

    test "captures custom decision function" do
      defmodule CustomEval do
        use AshHarness.Eval

        scenario "custom" do
          agent(nil)
          prompt("hi")
          auto_confirm({:custom, fn _intent -> :rejected end})

          gate :invariant do
            true
          end
        end
      end

      [scenario] = CustomEval.scenarios()
      assert {:custom, fun} = scenario.auto_confirm
      assert is_function(fun, 1)
      assert :rejected = fun.(:anything)
    end
  end

  describe "Runner option / scenario precedence" do
    test "scenario auto_confirm beats runner option" do
      scenario = %Scenario{
        name: "no driving",
        agent: nil,
        setup: fn -> %{} end,
        prompt: nil,
        gates: [
          %AshHarness.Eval.Gate{
            kind: :invariant,
            check: fn _ctx -> [{:invariant, true, true}] end
          }
        ],
        reports: [],
        auto_confirm: :always_reject
      }

      result = Runner.run(scenario, auto_confirm: :always_approve)
      assert result.passed
    end
  end

  describe "Runner.resolve_auto_confirm/2 precedence" do
    alias AshHarness.Eval.Runner
    alias AshHarness.Eval.Scenario

    test "scenario auto_confirm beats opts when both present" do
      scenario = %Scenario{
        name: "test",
        agent: nil,
        auto_confirm: :always_reject,
        gates: [],
        reports: []
      }

      # opts says approve, scenario says reject — scenario wins
      assert :always_reject = Runner.resolve_auto_confirm(scenario, auto_confirm: :always_approve)
    end

    test "opts value is used when scenario has no auto_confirm" do
      scenario = %Scenario{
        name: "test",
        agent: nil,
        auto_confirm: nil,
        gates: [],
        reports: []
      }

      assert :always_approve =
               Runner.resolve_auto_confirm(scenario, auto_confirm: :always_approve)

      assert :always_reject = Runner.resolve_auto_confirm(scenario, auto_confirm: :always_reject)
    end

    test "default :always_approve when neither side specifies" do
      scenario = %Scenario{
        name: "test",
        agent: nil,
        auto_confirm: nil,
        gates: [],
        reports: []
      }

      assert :always_approve = Runner.resolve_auto_confirm(scenario, [])
    end

    test "custom-fn override from scenario beats opts" do
      fun = fn _ -> :rejected end

      scenario = %Scenario{
        name: "test",
        agent: nil,
        auto_confirm: {:custom, fun},
        gates: [],
        reports: []
      }

      assert {:custom, ^fun} =
               Runner.resolve_auto_confirm(scenario, auto_confirm: :always_approve)
    end
  end

  describe "Runner.decide/2 honors the mode" do
    alias AshHarness.Eval.Runner

    test ":always_approve always returns :approved" do
      assert :approved = Runner.decide(:always_approve, :any_request)
    end

    test ":always_reject always returns :rejected" do
      assert :rejected = Runner.decide(:always_reject, :any_request)
    end

    test "{:custom, fn} delegates to the function" do
      approve = fn _ -> :approved end
      reject = fn _ -> :rejected end

      assert :approved = Runner.decide({:custom, approve}, %{id: "r1"})
      assert :rejected = Runner.decide({:custom, reject}, %{id: "r1"})
    end

    test "{:custom, fn} returning anything else defaults to :approved" do
      # decide/2 has a safety net for malformed custom fn returns
      weird = fn _ -> :maybe end
      assert :approved = Runner.decide({:custom, weird}, %{})
    end
  end
end
