defmodule AshHarness.Test.Restricted do
  @moduledoc false
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource],
    authorizers: [Ash.Policy.Authorizer]

  agent_annotations do
    description("Resource where mutations are unconditionally denied (test fixture).")
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:name, :string, allow_nil?: false, public?: true)
  end

  actions do
    defaults([:read])

    create :create do
      accept([:name])
      argument(:reasoning, :string, allow_nil?: true)
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if(always())
    end

    policy action_type(:create) do
      # Unconditionally deny — exercises PolicyGate refusal path.
      forbid_if(always())
    end
  end
end
