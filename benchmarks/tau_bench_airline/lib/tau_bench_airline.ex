defmodule TauBenchAirline do
  @moduledoc """
  AshHarness port of the τ-bench airline domain.

  Models a customer-support agent that helps airline customers change
  or cancel reservations, search flights, and so on. The agent's
  understanding of what it can do (read customer, change reservation,
  cancel reservation, search flights) is derived from Ash resources;
  policies enforce per-customer ownership.

  ## Methodology

  This port adapts τ-bench's airline tasks into `AshHarness.Eval`
  scenarios. Each scenario seeds the resource state from JSON
  fixtures, runs the airline agent against a user-simulator agent in
  a multi-turn loop (up to `max_turns`, default 12), and runs
  `gate :resource_state` assertions against the final state, plus
  diagnostic `report :trajectory` and `report :qualitative` blocks.

  Gate-pass-rate maps to τ-bench's task-pass metric. We document any
  divergence in `benchmarks/tau_bench_airline/README.md`.
  """
end
