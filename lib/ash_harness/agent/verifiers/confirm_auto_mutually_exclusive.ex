defmodule AshHarness.Agent.Verifiers.ConfirmAutoMutuallyExclusive do
  @moduledoc """
  No action may appear in both `behavior.confirm_before` and
  `behavior.auto_execute`.
  """

  use Spark.Dsl.Verifier

  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    confirm_before =
      Verifier.get_option(dsl_state, [:behavior], :confirm_before, [])
      |> List.wrap()
      |> MapSet.new()

    auto_execute =
      Verifier.get_option(dsl_state, [:behavior], :auto_execute, [])
      |> List.wrap()
      |> MapSet.new()

    overlap = MapSet.intersection(confirm_before, auto_execute) |> MapSet.to_list()

    case overlap do
      [] ->
        :ok

      [name | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [:behavior],
           message:
             "behavior on agent #{inspect(module)} declares :#{name} in both " <>
               "`confirm_before` and `auto_execute`; an action may belong to " <>
               "at most one"
         )}
    end
  end
end
