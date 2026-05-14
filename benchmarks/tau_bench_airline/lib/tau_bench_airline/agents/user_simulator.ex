defmodule TauBenchAirline.UserSimulator do
  @moduledoc """
  Empty-scope agent that role-plays the customer in a multi-turn
  conversation. Has no Ash actions; only converses on behalf of a
  simulated user with a goal.

  Note: An empty scope normally fails the `ScopeNotEmpty` verifier; the
  simulator gets a single read-only stub on `Customer.read` so the
  scope is non-empty per spec. The simulator never invokes it
  meaningfully.
  """

  use AshHarness.Agent, domains: [TauBenchAirline.Domain]

  identity do
    name "AirlineCustomer"
    description "Simulated airline customer role-playing a support request."
    actor %{id: "simulated-customer", role: :customer}
  end

  scope do
    resource TauBenchAirline.Customer do
      actions [:read]
    end
  end

  behavior do
    auto_execute [:read]
  end
end
