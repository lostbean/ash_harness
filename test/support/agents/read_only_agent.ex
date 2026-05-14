defmodule AshHarness.Test.ReadOnlyAgent do
  @moduledoc false
  use AshHarness.Agent, domains: [AshHarness.Test.Domain]

  identity do
    name("ReaderBot")
    description("Read-only agent over the test domain.")
    actor(%{id: "reader-bot", role: :bot})
  end

  scope do
    resource AshHarness.Test.Ticket do
      actions([:read])
    end

    resource AshHarness.Test.Project do
      actions([:read])
    end
  end

  behavior do
    auto_execute([:read])
  end
end
