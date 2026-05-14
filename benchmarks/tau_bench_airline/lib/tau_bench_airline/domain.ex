defmodule TauBenchAirline.Domain do
  @moduledoc false
  use Ash.Domain,
    extensions: [AshHarness.Domain],
    validate_config_inclusion?: false

  agent_domain do
    description "Airline customer support: reservations, flights, customers."
    term "reservation", "A booked itinerary tied to a customer."
    term "fare_class", "The class of fare on a reservation (basic/economy/premium/business)."
    term "loyalty_tier", "The customer's frequent-flyer tier."
  end

  resources do
    resource TauBenchAirline.Customer
    resource TauBenchAirline.Reservation
    resource TauBenchAirline.Flight
  end
end
