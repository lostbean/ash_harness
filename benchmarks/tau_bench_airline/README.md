# τ-bench Airline Port

A port of the τ-bench airline-domain customer-support task to
AshHarness + Ash resources.

v0.1.2 ships **ten** end-to-end scenarios driven by committed
cassettes:

| Scenario                       | What it tests                                                                            |
| ------------------------------ | ---------------------------------------------------------------------------------------- |
| `change_flight`                | agent moves a premium reservation to a later flight (`status == :changed`)               |
| `cancel_economy`               | agent cancels an economy reservation (`status == :cancelled`)                            |
| `refuse_basic_cancel`          | basic-fare reservation policy denial — status stays `:booked`; refusal logged            |
| `read_customer`                | pure-read loyalty-tier lookup; trajectory `excludes` mutating actions                    |
| `list_reservations`            | relation traversal from customer to reservations; no mutations expected                  |
| `search_by_origin_dest`        | flight search filtered by origin/destination; seat counts unchanged                      |
| `search_unknown_origin`        | error-path: search for `XYZ` returns no results; agent must not hallucinate              |
| `cross_customer_denial`        | runner answers `:always_reject` on confirmation; mutation cannot land                    |
| `change_flight_with_reasoning` | same goal as `change_flight` plus a diagnostic `report :qualitative` reasoning criterion |
| `budget_aware_multi_cancel`    | agent asked to cancel multiple reservations; mutations stay within per-turn budget       |

## Methodology

Each scenario:

1. Seeds Ash resources from `data/{customers,flights,reservations}.json`.
2. Builds a session via `AshHarness.Harness.new_session/2`.
3. Drives `Harness.run/3` + `Harness.resume/2` inside
   `ReqCassette.with_cassette/3`, capped at 12 turns.
4. Re-reads the resource state and asserts with `gate :resource_state`.
5. Captures diagnostics via `report :trajectory`.

Gate pass/fail is binary. The aggregate gate-pass-rate maps to
τ-bench's task-pass metric.

## Divergence from upstream τ-bench

- v0.1.2 ships 10 real scenarios; upstream τ-bench airline has ~50.
- No structured "user database" is modeled; ownership uses the
  customer's UUID rather than a τ-bench-specific key. Mapping table
  to be added once the upstream schema is verified (parent change's
  open question #3).
- The user simulator is an AshHarness agent rather than a separate
  τ-bench role-player.
- The agent's actor is `support-bot` (role `:bot`), which bypasses
  the per-customer ownership check on `Reservation` policies by
  design. `cross_customer_denial` therefore tests the confirmation
  gate (runner-level `:always_reject`) rather than the Ash
  authorizer.

## Reproducing

Default `mix test` runs everything in replay mode against committed
cassettes — no API key required:

```bash
cd benchmarks/tau_bench_airline
mix deps.get
mix tau_bench.run
```

To re-record cassettes (requires a live API key in env):

```bash
ASH_HARNESS_CASSETTE_MODE=record \
ANTHROPIC_API_KEY=sk-... \
mix tau_bench.run
```

Cassettes live under
`benchmarks/tau_bench_airline/test/cassettes/<scenario>.json` and
are committed to the repo.

Set the model used by the agent via the parent project's runtime
configuration:

```elixir
config :ash_harness_tau_bench, :model, "anthropic:claude-sonnet-4-5"
```

## Results

| Date       | Model                       | Gate-pass-rate | Scenarios            |
| ---------- | --------------------------- | -------------- | -------------------- |
| 2026-05-14 | anthropic:claude-sonnet-4-5 | 100 %          | 10 real, 0 placeholders |

The headline comes from `mix tau_bench.run` running in replay mode
against committed cassettes. Every scenario drives the real agent
through `Harness.run/3` + `Harness.resume/2`; reads/writes hit
`TauBenchAirline.Domain`, and LLM traffic comes from
`test/cassettes/tau_bench_airline_scenarios/*.json`.

Cassettes use `template: [preset: :llm]` so multi-turn replays stay
stable against fresh Anthropic `toolu_*` / `msg_*` / `req_*` IDs. See
`.claude/skills/req-cassette-llm/SKILL.md` for the full pattern.

Caveats baked into the v0.1.1 recording:

- The Anthropic API key header (`x-api-key`) in committed cassettes
  is replaced with a placeholder; `mix tau_bench.run` injects the
  same placeholder into ReqLLM's config when running in replay or
  default mode so cassette matching succeeds without a real key.
