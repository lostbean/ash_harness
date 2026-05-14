defmodule TauBenchAirline.Seeder do
  @moduledoc """
  Hydrates the τ-bench airline ETS resources from JSON fixtures under
  `benchmarks/tau_bench_airline/data/`.

  Records use **deterministic UUIDv5** identifiers derived from the
  human-readable `id` (`c-001`, `r-002`, …) in the JSON fixtures. This
  is essential for replayable cassettes: the LLM sees the same UUIDs
  on every run, so the request bodies sent to the provider match the
  recorded ones byte-for-byte.
  """

  alias TauBenchAirline.Customer
  alias TauBenchAirline.Flight
  alias TauBenchAirline.Reservation

  # Fixed namespace UUID for τ-bench airline seeding; any constant
  # UUIDv4 works — using one drawn once from `Ash.UUID.generate/0`.
  @namespace "8e9c5d3a-7f6b-4a1d-9a2c-d4b5e6f7a8b9"

  @doc """
  Seeds all resources from the default data path and returns a map of
  `%{customers: [...], reservations: [...], flights: [...], tasks: [...]}`.
  """
  @spec seed_all() :: map()
  def seed_all(data_dir \\ default_data_dir()) do
    customers = seed_customers(Path.join(data_dir, "customers.json"))
    flights = seed_flights(Path.join(data_dir, "flights.json"))
    reservations = seed_reservations(Path.join(data_dir, "reservations.json"))
    tasks = load_json(Path.join(data_dir, "tasks.json"))

    %{
      customers: customers,
      flights: flights,
      reservations: reservations,
      tasks: tasks
    }
  end

  def seed_customers(path) do
    # Wipe and reseed so re-runs see a clean slate without relying on
    # an upsert path through the create action (which doesn't accept
    # `:id` by design).
    purge(Customer)

    path
    |> load_json()
    |> Enum.map(fn row ->
      attrs = %{
        id: deterministic_id(row["id"]),
        name: row["name"],
        email: row["email"],
        loyalty_tier: String.to_atom(row["loyalty_tier"] || "basic")
      }

      Ash.Seed.seed!(Customer, attrs)
    end)
  end

  def seed_flights(path) do
    purge(Flight)

    path
    |> load_json()
    |> Enum.map(fn row ->
      {:ok, dt, _} = DateTime.from_iso8601(row["departure_at"])

      attrs = %{
        id: deterministic_id(row["id"]),
        origin: row["origin"],
        destination: row["destination"],
        departure_at: dt,
        seats_available: row["seats_available"] || 0,
        base_price: Decimal.new(row["base_price"] || "0")
      }

      Ash.Seed.seed!(Flight, attrs)
    end)
  end

  def seed_reservations(path) do
    purge(Reservation)

    path
    |> load_json()
    |> Enum.map(fn row ->
      {:ok, dt, _} = DateTime.from_iso8601(row["purchase_date"])

      attrs = %{
        id: deterministic_id(row["id"]),
        customer_id: deterministic_id(row["customer_id"]),
        flight_id: deterministic_id(row["flight_id"]),
        fare_class: String.to_atom(row["fare_class"] || "economy"),
        status: String.to_atom(row["status"] || "booked"),
        purchase_date: dt,
        ticket_price: Decimal.new(row["ticket_price"] || "0")
      }

      Ash.Seed.seed!(Reservation, attrs)
    end)
  end

  defp purge(resource) do
    case Ash.read(resource, authorize?: false) do
      {:ok, records} ->
        Enum.each(records, &Ash.destroy!(&1, authorize?: false))

      _ ->
        :ok
    end
  end

  @doc """
  Convert a human-readable fixture id (e.g. `"c-001"`) into a
  deterministic UUIDv5 so cassettes replay against the same UUIDs that
  were recorded.
  """
  @spec deterministic_id(String.t() | nil) :: String.t() | nil
  def deterministic_id(nil), do: nil

  def deterministic_id(human_id) when is_binary(human_id) do
    Uniq.UUID.uuid5(@namespace, human_id)
  end

  defp load_json(path) do
    case File.read(path) do
      {:ok, body} -> Jason.decode!(body)
      {:error, _} -> []
    end
  end

  defp default_data_dir do
    # `__DIR__` here is `<app>/lib/tau_bench_airline`. Walk up two
    # levels to the app root, then into `data/`.
    Path.expand("../../data", __DIR__)
  end
end
