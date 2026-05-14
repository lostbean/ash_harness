defmodule AshHarness.Domain.Verifier do
  @moduledoc """
  Enforces uniqueness of term `word` within a single domain.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Domain.Term
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    terms = Verifier.get_entities(dsl_state, [:agent_domain])

    duplicates =
      terms
      |> Enum.filter(&match?(%Term{}, &1))
      |> Enum.frequencies_by(& &1.word)
      |> Enum.filter(fn {_word, count} -> count > 1 end)
      |> Enum.map(fn {word, _} -> word end)

    case duplicates do
      [] ->
        :ok

      [word | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:agent_domain, :term],
           message: "agent_domain in #{inspect(module)} declares term \"#{word}\" more than once"
         )}
    end
  end
end
