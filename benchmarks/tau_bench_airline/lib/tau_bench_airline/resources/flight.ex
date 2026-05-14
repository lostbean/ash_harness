defmodule TauBenchAirline.Flight do
  @moduledoc false
  use Ash.Resource,
    domain: TauBenchAirline.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("A scheduled flight.")
  end

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:origin, :string, allow_nil?: false, public?: true)
    attribute(:destination, :string, allow_nil?: false, public?: true)
    attribute(:departure_at, :utc_datetime_usec, allow_nil?: false, public?: true)
    attribute(:seats_available, :integer, default: 0, public?: true)
    attribute(:base_price, :decimal, default: Decimal.new("0"), public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])

    read :search do
      argument(:origin, :string, allow_nil?: true)
      argument(:destination, :string, allow_nil?: true)

      filter(
        expr(
          (is_nil(^arg(:origin)) or origin == ^arg(:origin)) and
            (is_nil(^arg(:destination)) or destination == ^arg(:destination))
        )
      )
    end
  end
end
