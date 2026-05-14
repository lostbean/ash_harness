defmodule AshHarness.Resource do
  @moduledoc """
  Spark DSL extension that adds the `agent_annotations` section to an
  Ash resource.

  Use it by adding `extensions: [AshHarness.Resource]` to a resource:

      defmodule MyApp.Ticket do
        use Ash.Resource,
          domain: MyApp.Ticketing,
          extensions: [AshHarness.Resource]

        agent_annotations do
          description "A unit of work in the support queue."
          traversable [:project, :comments]
          hidden_attributes [:internal_notes]
          hint :assign, "Use this to delegate work to a teammate."
        end

        # ...
      end

  Introspection lives in `AshHarness.Resource.Info`.
  """

  @hint %Spark.Dsl.Entity{
    name: :hint,
    describe: """
    A per-action agent-facing hint shown alongside the action description.
    """,
    examples: [
      ~s|hint :assign, "Use this to delegate work to a teammate."|
    ],
    target: AshHarness.Resource.Hint,
    args: [:action_name, :text],
    schema: [
      action_name: [
        type: :atom,
        required: true,
        doc: "The action this hint applies to."
      ],
      text: [
        type: :string,
        required: true,
        doc: "The hint text shown to the agent."
      ]
    ]
  }

  @agent_annotations %Spark.Dsl.Section{
    name: :agent_annotations,
    describe: """
    Agent-facing metadata for this resource: a description, hints per
    action, traversable relationships, and hidden attributes.
    """,
    examples: [
      """
      agent_annotations do
        description "A unit of work in the support queue."
        traversable [:project, :comments]
        hidden_attributes [:internal_notes]
        hint :assign, "Use this to delegate work to a teammate."
      end
      """
    ],
    schema: [
      description: [
        type: :string,
        required: true,
        doc: "A short, agent-facing description of this resource."
      ],
      traversable: [
        type: {:list, :atom},
        default: [],
        doc: "Relationships the agent is allowed to follow when this resource is in scope."
      ],
      hidden_attributes: [
        type: {:list, :atom},
        default: [],
        doc: "Attributes the agent must not see in rendered context or tool results."
      ]
    ],
    entities: [
      @hint
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@agent_annotations],
    transformers: [AshHarness.Resource.Transformer],
    verifiers: [AshHarness.Resource.Verifier]
end
