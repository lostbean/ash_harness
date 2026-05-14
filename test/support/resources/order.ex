defmodule AshHarness.Test.Order do
  @moduledoc """
  Type-coverage resource: exercises `:decimal`, `{:array, :string}`,
  and `:map` types in the canonical schema mapper.
  """
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource]

  agent_annotations do
    description("An order, used to exercise type-mapping coverage.")
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:total, :decimal, allow_nil?: false, public?: true)

    attribute(:tags, {:array, :string},
      default: [],
      public?: true
    )

    attribute(:metadata, :map, default: %{}, public?: true)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])
  end
end
