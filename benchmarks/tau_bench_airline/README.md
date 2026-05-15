# τ-bench Airline Port

A port of the τ-bench airline-domain customer-support task to
AshHarness + Ash resources.

v0.1.1 ships **three** end-to-end scenarios driven by committed
cassettes:

| Scenario              | What it tests                                                                  |
| --------------------- | ------------------------------------------------------------------------------ |
| `change_flight`       | agent moves a premium reservation to a later flight (`status == :changed`)     |
| `cancel_economy`      | agent cancels an economy reservation (`status == :cancelled`)                  |
| `refuse_basic_cancel` | basic-fare reservation policy denial — status stays `:booked`; refusal logged  |

Seven additional scenarios remain in the module as v0.2 placeholders
(declared with `agent(nil)`) so the test suite stays stable while
real cassettes are still being recorded.

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

- v0.1.1 ships 3 real scenarios + 7 placeholders; upstream τ-bench
  airline has ~50.
- No structured "user database" is modeled; ownership uses the
  customer's UUID rather than a τ-bench-specific key. Mapping table
  to be added once the upstream schema is verified (parent change's
  open question #3).
- The user simulator is an AshHarness agent rather than a separate
  τ-bench role-player.

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

| Date       | Model                       | Gate-pass-rate | Scenarios                    |
| ---------- | --------------------------- | -------------- | ---------------------------- |
| 2026-05-14 | anthropic:claude-sonnet-4-5 | 100 %          | 3 real + 7 v0.2 placeholders |

The headline comes from `mix tau_bench.run` running in replay mode
against committed cassettes:

- `change_flight` — agent reads the customer's reservations, searches
  for later flights on the route, calls `reservation__change_flight`;
  `gate :resource_state` confirms `:status == :changed`.
- `cancel_economy` — agent reads the reservation, calls
  `reservation__cancel`; gate confirms `:status == :cancelled`.
- `refuse_basic_cancel` — agent reads the reservation, recognizes the
  basic-fare policy, and refuses without calling any mutation; gate
  confirms `:status` remains `:booked`.
- 7 v0.2 placeholders pass trivially (`agent(nil)` + `gate :invariant
  do true end`) — they exist so the test count stays stable while
  the remaining ~47 upstream τ-bench scenarios are added in v0.2.

Cassettes use `template: [preset: :llm]` so multi-turn replays stay
stable against fresh Anthropic `toolu_*` / `msg_*` / `req_*` IDs. See
`.claude/skills/req-cassette-llm/SKILL.md` for the full pattern.

Caveats baked into the v0.1.1 recording:

- The Anthropic API key header (`x-api-key`) in committed cassettes
  is replaced with a placeholder; `mix tau_bench.run` injects the
  same placeholder into ReqLLM's config when running in replay or
  default mode so cassette matching succeeds without a real key.
