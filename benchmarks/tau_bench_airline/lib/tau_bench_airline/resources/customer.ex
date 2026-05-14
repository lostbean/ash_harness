defmodule TauBenchAirline.Customer do
  @moduledoc false
  use Ash.Resource,
    domain: TauBenchAirline.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("An airline customer.")
    traversable([:reservations])
  end

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:email, :string, allow_nil?: false, public?: true)

    attribute(:loyalty_tier, :atom,
      constraints: [one_of: [:basic, :silver, :gold, :platinum]],
      default: :basic,
      public?: true
    )
  end

  relationships do
    has_many(:reservations, TauBenchAirline.Reservation, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
