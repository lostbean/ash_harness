defmodule AshHarness.Agent.Transformers.ComputeToolSet do
  @moduledoc """
  Derives the agent's canonical tool list from the scoped (resource,
  action) pairs and persists it under `:tool_list`.

  Each entry is an `%AshHarness.Schema.Canonical{}` struct.
  """

  use Spark.Dsl.Transformer

  alias AshHarness.Schema
  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshHarness.Agent.Transformers.ComputeReachability), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    scope_entries = Transformer.get_entities(dsl_state, [:scope])

    tools =
      for %AshHarness.Agent.Scope.ResourceEntry{module: resource, actions: actions} <-
            scope_entries,
          action_name <- actions do
        Schema.canonical_for(resource, action_name)
      end

    {:ok, Transformer.persist(dsl_state, :tool_list, tools)}
  end
end
