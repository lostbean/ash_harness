defmodule AshHarness.Agent.Verifiers.ScopeNotEmpty do
  @moduledoc """
  Refuses an agent module whose `scope` block contains no resource
  entries.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    case Verifier.get_entities(dsl_state, [:scope]) do
      [] ->
        module = Verifier.get_persisted(dsl_state, :module)

        {:error,
         DslError.exception(
           module: module,
           path: [:scope],
           message:
             "AshHarness agent #{inspect(module)} declares an empty scope; declare at least one (resource, actions) entry."
         )}

      _ ->
        :ok
    end
  end
end
