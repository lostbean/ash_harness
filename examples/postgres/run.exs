# A runnable demo that mirrors `examples/triage/run.exs` but with the
# resources backed by AshPostgres instead of ETS. Run from the
# repository root:
#
#     # Optional: set DATABASE_URL or rely on the default
#     # ecto://postgres:postgres@localhost/ash_harness_postgres_example
#     mix run examples/postgres/run.exs
#
# The harness, gates, eval framework, and ToolGen are data-layer
# agnostic (ADR 0008); only the `data_layer:` and the `postgres do`
# block differ from `test/support/resources/`.

unless Code.ensure_loaded?(AshPostgres.DataLayer) do
  IO.puts("""
  This example requires `ash_postgres`. It is declared `optional: true`
  in ash_harness's `mix.exs`, so:

      mix.exs:
        {:ash_postgres, "~> 2.0"}

      $ mix deps.get

  Then ensure a Postgres server is reachable; the default URL is

      ecto://postgres:postgres@localhost/ash_harness_postgres_example

  Override with the DATABASE_URL env var. After that, re-run:

      mix run examples/postgres/run.exs
  """)

  System.halt(0)
end

# ---------- Repo ----------

defmodule AshHarness.Examples.Postgres.Repo do
  @moduledoc false
  use AshPostgres.Repo, otp_app: :ash_harness

  def installed_extensions, do: ["ash-functions"]
  def min_pg_version, do: %Version{major: 14, minor: 0, patch: 0}
end

database_url =
  System.get_env("DATABASE_URL") ||
    "ecto://postgres:postgres@localhost/ash_harness_postgres_example"

Application.put_env(:ash_harness, AshHarness.Examples.Postgres.Repo,
  url: database_url,
  pool_size: 2,
  log: false
)

# ---------- Domain & resources ----------

defmodule AshHarness.Examples.Postgres.Domain do
  @moduledoc false
  use Ash.Domain,
    extensions: [AshHarness.Domain],
    validate_config_inclusion?: false

  agent_domain do
    description("Postgres-backed example domain.")
    term("ticket", "A unit of work in the support queue.")
  end

  resources do
    resource(AshHarness.Examples.Postgres.Ticket)
  end
end

defmodule AshHarness.Examples.Postgres.Ticket do
  @moduledoc false
  use Ash.Resource,
    domain: AshHarness.Examples.Postgres.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshHarness.Resource],
    authorizers: [Ash.Policy.Authorizer]

  agent_annotations do
    description("A unit of work in the support queue.")
  end

  postgres do
    table("postgres_example_tickets")
    repo(AshHarness.Examples.Postgres.Repo)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:open, :resolved]],
      default: :open,
      allow_nil?: false,
      public?: true
    )
  end

  actions do
    defaults([:read, :destroy])

    create :open_ticket do
      accept([:title])
    end

    update :resolve do
      change(set_attribute(:status, :resolved))
    end
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end
end

defmodule AshHarness.Examples.Postgres.Agent do
  @moduledoc false
  use AshHarness.Agent, domains: [AshHarness.Examples.Postgres.Domain]

  identity do
    name("PostgresTriage")
    description("Demonstrates AshHarness with an AshPostgres-backed resource.")
    actor(%{id: "postgres-example-bot", role: :bot})
  end

  scope do
    resource AshHarness.Examples.Postgres.Ticket do
      actions([:read, :open_ticket, :resolve])
    end
  end

  behavior do
    auto_execute([:read, :open_ticket, :resolve])
  end
end

# ---------- Boot Repo + migrate ----------

{:ok, _repo} = AshHarness.Examples.Postgres.Repo.start_link()

# Best-effort schema setup. Falls back to a raw CREATE TABLE so the
# example doesn't need `mix ash.codegen` boilerplate just to run.
case Ecto.Adapters.SQL.query(
       AshHarness.Examples.Postgres.Repo,
       """
       CREATE TABLE IF NOT EXISTS postgres_example_tickets (
         id uuid PRIMARY KEY,
         title text NOT NULL,
         status text NOT NULL DEFAULT 'open'
       );
       """,
       []
     ) do
  {:ok, _} ->
    :ok

  {:error, %{__struct__: _, message: msg}} ->
    IO.puts("Could not initialize schema: #{msg}")
    System.halt(1)
end

# ---------- Demo ----------

agent = AshHarness.Examples.Postgres.Agent

IO.puts("Agent: #{AshHarness.Agent.Info.name(agent)}")
IO.puts("Description: #{AshHarness.Agent.Info.description(agent)}")
IO.puts("Repo: #{inspect(AshHarness.Examples.Postgres.Repo)}")
IO.puts("Table: postgres_example_tickets\n")

IO.puts("Tool list (#{length(AshHarness.Agent.Info.tool_list(agent))} tools):")

for tool <- AshHarness.Agent.Info.tool_list(agent) do
  IO.puts("  - #{tool.tool_name} :: #{inspect(tool.action_type)}")
end

# Exercise the live Postgres path: create, read, resolve.
ticket =
  AshHarness.Examples.Postgres.Ticket
  |> Ash.Changeset.for_create(:open_ticket, %{title: "Customer can't log in"})
  |> Ash.create!()

IO.puts("\nCreated ticket #{ticket.id} (status: #{ticket.status})")

[round_trip] = Ash.read!(AshHarness.Examples.Postgres.Ticket)
IO.puts("Read back from Postgres: #{inspect(round_trip.title)}")

resolved =
  round_trip
  |> Ash.Changeset.for_update(:resolve, %{})
  |> Ash.update!()

IO.puts("Resolved: status=#{resolved.status}")

# Clean up so re-running the script stays idempotent.
Ash.destroy!(resolved)

IO.puts(
  "\nDone. The agent's tool surface, gates, and renderers are identical to the ETS example."
)
