defmodule AshHarness.Agent.Verifiers.DelegateAliasesUnique do
  @moduledoc """
  Verifies that no two `delegate` entries in an agent's `delegates_to`
  block declare the same `as:` alias (case-insensitive). The LLM
  resolves `delegate(target, ...)` by case-insensitive string match, so
  duplicate aliases are ambiguous and rejected at compile time.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Delegation.DelegateEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    delegates =
      dsl_state
      |> Verifier.get_entities([:delegates_to])
      |> Enum.filter(&match?(%DelegateEntry{}, &1))

    case find_duplicate(delegates) do
      nil ->
        :ok

      {alias_lower, conflicts} ->
        {:error,
         DslError.exception(
           module: module,
           path: [:delegates_to, :delegate],
           message:
             "duplicate delegate alias #{inspect(alias_lower)} on agent " <>
               "#{inspect(module)}: #{format_conflicts(conflicts)}. Aliases are matched " <>
               "case-insensitively; pick a unique `as: \"<alias>\"` for each delegate."
         )}
    end
  end

  defp find_duplicate(delegates) do
    delegates
    |> Enum.group_by(fn %DelegateEntry{as: a} -> normalize(a) end)
    |> Enum.find(fn {_lower, entries} -> length(entries) > 1 end)
  end

  defp normalize(nil), do: nil
  defp normalize(s) when is_binary(s), do: String.downcase(s)

  defp format_conflicts(entries) do
    Enum.map_join(entries, ", ", fn %DelegateEntry{agent_module: m, as: a} ->
      "#{inspect(m)} (as: #{inspect(a)})"
    end)
  end
end
