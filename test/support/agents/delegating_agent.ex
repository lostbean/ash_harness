defmodule AshHarness.Test.DelegatingAgent do
  @moduledoc false
  use AshHarness.Agent, domains: [AshHarness.Test.Domain]

  identity do
    name("DelegatorBot")
    description("Delegates account-y work to the triage bot.")
    actor(%{id: "delegator-bot", role: :bot})
  end

  scope do
    resource AshHarness.Test.Project do
      actions([:read])
    end
  end

  behavior do
    auto_execute([:read])
  end

  delegates_to do
    delegate(AshHarness.Test.TriageAgent, "Ticketing-related questions.")
  end
end
