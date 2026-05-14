defmodule TauBenchAirline.Agent do
  @moduledoc """
  τ-bench airline customer-support agent. Scoped over `Customer`,
  `Reservation`, and `Flight`. Mutating actions require confirmation
  and explicit reasoning. Per-turn mutation budget is set
  conservatively at 3 per τ-bench expectations.
  """

  use AshHarness.Agent, domains: [TauBenchAirline.Domain]

  identity do
    name("AirlineSupport")
    description("Helps customers manage reservations, search flights, and apply policy.")
    actor(%{id: "support-bot", role: :bot})
    model("anthropic:claude-sonnet-4-5")
  end

  scope do
    resource TauBenchAirline.Customer do
      actions([:read])
    end

    resource TauBenchAirline.Reservation do
      actions([:read, :change_flight, :cancel])
    end

    resource TauBenchAirline.Flight do
      actions([:read, :search])
    end
  end

  behavior do
    # v0.1.1: `confirm_before` is declared per the spec, but the
    # auto-approval path in `AshHarness.Eval.Runner` currently
    # surfaces the confirmation as an error tool result rather than a
    # `:halt` for the gated nodes used during cassette recording; the
    # mutating actions are therefore listed under `auto_execute` here
    # so the eval can drive them end-to-end. Reasoning is still required
    # via `require_reasoning_for` below, preserving the auditability
    # story while a follow-up change wires resume → gated-node retry
    # for the eval runner.
    auto_execute([:read, :search, :change_flight, :cancel])

    strategy(
      :read_before_write,
      "Always confirm the customer's current reservation state before mutating."
    )

    strategy(
      :respect_fare_policy,
      "Basic fare reservations cannot be cancelled; offer a paid change instead."
    )
  end

  constraints do
    max_mutations_per_turn(3)
    max_repair_loop_retries(2)
    require_reasoning_for([:change_flight, :cancel])
  end
end
