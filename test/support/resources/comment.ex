defmodule AshHarness.Test.Comment do
  @moduledoc false
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("A comment on a ticket.")
    traversable([:ticket])
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:body, :string, allow_nil?: false, public?: true)
  end

  relationships do
    belongs_to(:ticket, AshHarness.Test.Ticket, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
