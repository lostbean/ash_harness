defmodule AshHarness.Agent.Transformers.ComputeReachability do
  @moduledoc """
  Builds the agent's reachability graph and persists it under
  `:reachability_graph`.

  See `AshHarness.Reachability` for the algorithm and graph shape.
  """

  use Spark.Dsl.Transformer

  alias AshHarness.Reachability
  alias Spark.Dsl.Transformer

  @impl true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    graph = Reachability.build(dsl_state)
    {:ok, Transformer.persist(dsl_state, :reachability_graph, graph)}
  end
end
