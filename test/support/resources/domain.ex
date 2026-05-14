defmodule AshHarness.Test.Domain do
  @moduledoc false
  use Ash.Domain,
    extensions: [AshHarness.Domain],
    validate_config_inclusion?: false

  agent_domain do
    description("Test ticketing domain used by the AshHarness suite.")
    term("ticket", "A unit of work in the support queue.")
    term("triage", "Initial evaluation and assignment of incoming tickets.")
  end

  resources do
    resource(AshHarness.Test.Project)
    resource(AshHarness.Test.Ticket)
    resource(AshHarness.Test.Comment)
    resource(AshHarness.Test.Member)
    resource(AshHarness.Test.Order)
    resource(AshHarness.Test.Restricted)
  end
end
