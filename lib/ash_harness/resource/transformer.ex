defmodule AshHarness.Resource.Transformer do
  @moduledoc """
  Persists derived agent-annotation state on the DSL:

    * `:ash_harness_hints_by_action` — `%{atom() => String.t()}` map
      keyed by action name (last hint wins on duplicates).
    * `:ash_harness_traversable` — `MapSet.t(atom())` of relationship
      names declared traversable.
    * `:ash_harness_hidden_attributes` — `MapSet.t(atom())` of
      attribute names hidden from agents.
    * `:ash_harness_agent_annotated?` — `true` iff `agent_annotations`
      section was declared on this resource.

  Validation of these references is deferred to `AshHarness.Resource.Verifier`.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(Ash.Resource.Transformers.SetPrimaryActions), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    section_present? = section_declared?(dsl_state)

    hints =
      dsl_state
      |> Transformer.get_entities([:agent_annotations])
      |> Enum.into(%{}, fn %AshHarness.Resource.Hint{action_name: name, text: text} ->
        {name, text}
      end)

    traversable =
      dsl_state
      |> Transformer.get_option([:agent_annotations], :traversable)
      |> Kernel.||([])
      |> MapSet.new()

    hidden =
      dsl_state
      |> Transformer.get_option([:agent_annotations], :hidden_attributes)
      |> Kernel.||([])
      |> MapSet.new()

    dsl_state =
      dsl_state
      |> Transformer.persist(:ash_harness_hints_by_action, hints)
      |> Transformer.persist(:ash_harness_traversable, traversable)
      |> Transformer.persist(:ash_harness_hidden_attributes, hidden)
      |> Transformer.persist(:ash_harness_agent_annotated?, section_present?)

    {:ok, dsl_state}
  end

  defp section_declared?(dsl_state) do
    case Transformer.fetch_option(dsl_state, [:agent_annotations], :description) do
      {:ok, _} -> true
      :error -> Transformer.get_entities(dsl_state, [:agent_annotations]) != []
    end
  end
end
