defmodule AshHarness.Test.TriageAgent do
  @moduledoc false
  use AshHarness.Agent, domains: [AshHarness.Test.Domain]

  identity do
    name("TriageBot")
    description("Triages incoming support tickets.")
    actor(%{id: "triage-bot", role: :bot})
    model("anthropic:claude-sonnet-4-5")
  end

  scope do
    resource AshHarness.Test.Ticket do
      actions([:read, :open_ticket, :assign])
    end

    resource AshHarness.Test.Project do
      actions([:read])
    end

    resource AshHarness.Test.Member do
      actions([:read, :by_workload])
    end

    resource AshHarness.Test.Restricted do
      actions([:read, :create])
    end
  end

  behavior do
    confirm_before([:assign])
    auto_execute([:read, :open_ticket])
    strategy(:default, "Read before writing; assign to least-loaded teammate.")
  end

  constraints do
    max_mutations_per_turn(5)
    require_reasoning_for([:assign])
  end
end
