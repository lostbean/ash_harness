# Postgres Example (gated)

Mirrors the `triage` example but backed by `AshPostgres`. Gated by
`MIX_ENV=postgres mix test` per ADR 0008.

This directory is a placeholder for v0.1.0 — the Postgres-backed
resource definitions wire identically to ETS resources except for the
`data_layer:` and the corresponding `postgres do ... end` block.

To enable:

1. Add `{:ash_postgres, "~> 2.0"}` to your host application.
2. Mirror the Ticket / Project / Member resources with
   `data_layer: AshPostgres.DataLayer`.
3. Run `MIX_ENV=postgres mix test --only postgres` to verify.

The harness, gates, and eval framework are data-layer agnostic; no
changes there.
