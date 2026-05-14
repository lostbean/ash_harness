defmodule TauBenchAirline.Reservation do
  @moduledoc false
  use Ash.Resource,
    domain: TauBenchAirline.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource],
    authorizers: [Ash.Policy.Authorizer]

  agent_annotations do
    description("A booked itinerary tied to a customer.")
    traversable([:customer, :flight])
    hint(:change_flight, "Use this to move the customer to a different flight.")
    hint(:cancel, "Use this when the customer wants to cancel the reservation.")
  end

  ets do
    private?(false)
  end

  attributes do
    uuid_primary_key(:id)

    attribute(:fare_class, :atom,
      constraints: [one_of: [:basic, :economy, :premium, :business]],
      default: :economy,
      allow_nil?: false,
      public?: true
    )

    attribute(:status, :atom,
      constraints: [one_of: [:booked, :changed, :cancelled]],
      default: :booked,
      allow_nil?: false,
      public?: true
    )

    attribute(:purchase_date, :utc_datetime_usec,
      default: &DateTime.utc_now/0,
      allow_nil?: false,
      public?: true
    )

    attribute(:ticket_price, :decimal,
      default: Decimal.new("0"),
      public?: true
    )
  end

  relationships do
    belongs_to(:customer, TauBenchAirline.Customer, public?: true, allow_nil?: false)
    belongs_to(:flight, TauBenchAirline.Flight, public?: true, allow_nil?: false)
  end

  actions do
    defaults([:read, :destroy, create: :*])

    update :change_flight do
      accept([:flight_id])
      argument(:reasoning, :string, allow_nil?: true)
      change(set_attribute(:status, :changed))
    end

    update :cancel do
      accept([])
      argument(:reasoning, :string, allow_nil?: true)

      validate(attribute_does_not_equal(:fare_class, :basic),
        message: "basic fare reservations cannot be cancelled per policy"
      )

      change(set_attribute(:status, :cancelled))
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type([:update, :destroy]) do
      # Allow the support-bot actor (used by the τ-bench agent) to act
      # on behalf of any customer; otherwise require ownership.
      authorize_if(expr(^actor(:role) == :bot))
      authorize_if(expr(customer_id == ^actor(:customer_id)))
    end
  end
end
