defmodule AshHarness.Test.Member do
  @moduledoc false
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("A teammate who can be assigned tickets.")
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
    attribute(:open_ticket_count, :integer, default: 0, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])

    read :by_workload do
      prepare(build(sort: [open_ticket_count: :asc]))
    end
  end
end
