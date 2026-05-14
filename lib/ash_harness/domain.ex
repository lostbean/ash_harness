defmodule AshHarness.Domain do
  @moduledoc """
  Spark DSL extension that adds the `agent_domain` section to an Ash
  domain, with a description and ubiquitous-language `term` entries.

      defmodule MyApp.Ticketing do
        use Ash.Domain, extensions: [AshHarness.Domain]

        agent_domain do
          description "Customer support work tracking."
          term "ticket", "A unit of work — a customer's request."
          term "triage", "Initial evaluation and assignment."
        end
      end

  Introspection lives in `AshHarness.Domain.Info`.
  """

  @term %Spark.Dsl.Entity{
    name: :term,
    describe: "A vocabulary entry: a word and its definition for the agent.",
    examples: [
      ~s|term "ticket", "A unit of work — a customer's request."|
    ],
    target: AshHarness.Domain.Term,
    args: [:word, :definition],
    schema: [
      word: [
        type: :string,
        required: true,
        doc: "The vocabulary word (lowercased domain term)."
      ],
      definition: [
        type: :string,
        required: true,
        doc: "A short definition the agent can read."
      ]
    ]
  }

  @agent_domain %Spark.Dsl.Section{
    name: :agent_domain,
    describe: """
    Agent-facing metadata for the domain: a description and a
    vocabulary of terms that downstream agents include in their
    rendered context.
    """,
    examples: [
      """
      agent_domain do
        description "Customer support work tracking."
        term "ticket", "A unit of work — a customer's request."
      end
      """
    ],
    schema: [
      description: [
        type: {:or, [:string, nil]},
        default: nil,
        doc: "Optional agent-facing description of the domain."
      ]
    ],
    entities: [@term]
  }

  use Spark.Dsl.Extension,
    sections: [@agent_domain],
    transformers: [AshHarness.Domain.Transformer],
    verifiers: [AshHarness.Domain.Verifier]
end
