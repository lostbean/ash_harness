defmodule AshHarness.Test.Ticket do
  @moduledoc false
  use Ash.Resource,
    domain: AshHarness.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshHarness.Resource],
    authorizers: [Ash.Policy.Authorizer]

  agent_annotations do
    description("A unit of work in the support queue.")
    traversable([:project, :comments, :parent_ticket])
    hidden_attributes([:internal_notes])
    hint(:assign, "Use this to delegate the ticket to a teammate.")
    hint(:resolve, "Only valid when status is :in_progress.")
  end

  ets do
    private?(true)
  end

  attributes do
    uuid_primary_key(:id)
    attribute(:title, :string, allow_nil?: false, public?: true)

    attribute(:status, :atom,
      constraints: [one_of: [:open, :in_progress, :resolved, :closed]],
      default: :open,
      allow_nil?: false,
      public?: true
    )

    attribute(:priority, :atom,
      constraints: [one_of: [:low, :medium, :high]],
      default: :medium,
      allow_nil?: false,
      public?: true
    )

    attribute(:assigned_to, :string, public?: true)
    attribute(:internal_notes, :string, public?: true)
  end

  relationships do
    belongs_to(:project, AshHarness.Test.Project, public?: true)
    has_many(:comments, AshHarness.Test.Comment, public?: true)
    belongs_to(:parent_ticket, AshHarness.Test.Ticket, public?: true)
  end

  actions do
    defaults([:read, :destroy])

    create :open_ticket do
      accept([:title, :priority, :project_id])
    end

    update :assign do
      accept([:assigned_to])
      argument(:reasoning, :string, allow_nil?: true)
    end

    update :resolve do
      accept([])
      validate(attribute_equals(:status, :in_progress))
      change(set_attribute(:status, :resolved))
    end
  end

  policies do
    policy always() do
      authorize_if(always())
    end
  end
end
