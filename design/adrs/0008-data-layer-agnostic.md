# ADR 0008 — Data-layer agnostic; ETS default

## Status

Accepted (2026-05-08).

## Context

What data layer do AshHarness's bundled examples and benchmark use?

Options:

- ETS-only (zero infra, fast tests).
- AshPostgres (production-realistic, requires Docker).
- Both supported (library is data-layer-agnostic by construction).

## Decision

The library itself is data-layer-agnostic — we operate on
`Ash.Resource` and `Ash.Domain`, never on a specific data layer.

For bundled examples and τ-bench port:

- **Default**: ETS (`Ash.DataLayer.Ets`). All test resources, the
  README quickstart, the `mix new --template` scaffold use ETS.
- **Optional**: an `examples/postgres/` directory shows the same
  examples backed by AshPostgres for users who want production
  flavor.
- The τ-bench airline domain port is delivered as a separate package
  (`ash_harness_tau_bench`) that defaults to ETS but supports both.

## Consequences

### Pros

- Anyone can clone, run `mix test`, `mix run examples/quickstart.exs`,
  and see the demo work — zero infra.
- AshHarness doesn't take a hard dependency on AshPostgres.
- Production users wire their own data layer; nothing in AshHarness
  cares.

### Cons

- The ETS-default examples don't demonstrate transactions, optimistic
  locking, or other Postgres-flavored concerns. We document these as
  "see AshPostgres docs."

### Test resources

Test resources (Ticket, Project, Comment, Member) live under
`test/support/resources/` and use ETS. Same fixtures power the harness
tests, the eval framework tests, and the public examples.

### What we depend on

- `{:ash, "~> 3.0"}` — required.
- `{:spark, "~> 2.0"}` — required (DSL infra).
- `{:jido_composer, "~> 0.5"}` — required (runtime).
- `{:jason, "~> 1.4"}` — required (JSON encode).
- `{:telemetry, "~> 1.0"}` — required.
- `{:ash_postgres, "~> 2.0"}` — `optional: true`. Examples and
  tests only when `MIX_ENV=postgres`.

## Alternatives considered

1. **AshPostgres-only for τ-bench.** Rejected — adds infra friction for
   a primary "show this works" benchmark.
2. **ETS-only library.** Rejected — actively hostile to Postgres
   users.
3. **Make τ-bench port a separate hex package.** Accepted (see above);
   keeps the main library lean.
