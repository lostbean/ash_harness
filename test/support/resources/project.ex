defmodule AshHarness.Test.Project do
  @moduledoc false
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("A project containing tickets.")
    traversable([:tickets])
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end

  relationships do
    has_many(:tickets, AshHarness.Test.Ticket, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
