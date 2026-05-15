defmodule AshHarness.Test.Alt.Ticket do
  @moduledoc false
  # A second resource whose last name-segment ("Ticket") collides with
  # `AshHarness.Test.Ticket`. Exists solely so the
  # `ToolNamesUnique` verifier has something to refuse.
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("Alternate-namespace ticket for tool-name-conflict tests.")
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, public?: true)
  end

  actions do
    defaults([:read])
  end
end
