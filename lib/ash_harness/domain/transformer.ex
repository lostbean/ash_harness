defmodule AshHarness.Domain.Transformer do
  @moduledoc """
  Persists a `:ash_harness_terms_by_word` map and a
  `:ash_harness_domain_annotated?` flag into the domain's DSL state.
  """

  use Spark.Dsl.Transformer

  alias AshHarness.Domain.Term
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    terms = Transformer.get_entities(dsl_state, [:agent_domain])

    by_word =
      terms
      |> Enum.filter(&match?(%Term{}, &1))
      |> Enum.into(%{}, fn %Term{word: w, definition: d} -> {w, d} end)

    description =
      Transformer.get_option(dsl_state, [:agent_domain], :description, nil)

    annotated? =
      description != nil or terms != []

    dsl_state =
      dsl_state
      |> Transformer.persist(:ash_harness_terms_by_word, by_word)
      |> Transformer.persist(:ash_harness_domain_annotated?, annotated?)

    {:ok, dsl_state}
  end
end
