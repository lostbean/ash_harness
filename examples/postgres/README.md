# Postgres Example

A runnable demo that mirrors `examples/triage/` but with the resource
backed by `AshPostgres` instead of ETS. Demonstrates ADR 0008: the
harness, gates, eval framework, and ToolGen are data-layer agnostic;
only the `data_layer:` and the `postgres do` block differ.

## Prerequisites

1. `ash_postgres` is declared `optional: true` in this library, so the
   host application must depend on it:

   ```elixir
   {:ash_postgres, "~> 2.0"}
   ```

   then `mix deps.get`.

2. A reachable Postgres server. By default the script connects to:

   ```
   ecto://postgres:postgres@localhost/ash_harness_postgres_example
   ```

   Override via `DATABASE_URL`.

## Run

```
mix run examples/postgres/run.exs
```

The script:

1. Defines a `Domain`, a `Ticket` resource (with `data_layer:
   AshPostgres.DataLayer`), and an agent over them.
2. Boots a Repo and creates the `postgres_example_tickets` table if it
   doesn't exist.
3. Prints the agent's tool list and round-trips a ticket through
   `:open_ticket` → `:read` → `:resolve` → `:destroy`.

If `AshPostgres` isn't loaded, the script exits with installation hints
and a non-zero status code is **not** raised — it is treated as a
deferred-environment, not a failure.
