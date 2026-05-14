defmodule AshHarness.Domain.Info do
  @moduledoc """
  Introspection for domains that use the `AshHarness.Domain` extension.
  """

  alias AshHarness.Domain.Term

  @doc """
  Returns the agent-facing description for the domain, or `nil`.
  """
  @spec description(module() | map()) :: String.t() | nil
  def description(domain_or_dsl) do
    if spark_dsl?(domain_or_dsl) do
      Spark.Dsl.Extension.get_opt(
        domain_or_dsl,
        [:agent_domain],
        :description,
        nil
      )
    else
      nil
    end
  end

  @doc """
  Returns the domain's `term` entities as a list of `%Term{}` structs.
  """
  @spec terms(module() | map()) :: [Term.t()]
  def terms(domain_or_dsl) do
    if spark_dsl?(domain_or_dsl) do
      domain_or_dsl
      |> Spark.Dsl.Extension.get_entities([:agent_domain])
      |> Enum.filter(&match?(%Term{}, &1))
    else
      []
    end
  end

  @doc """
  Looks up the definition for a given word; returns `nil` when no term
  matches.
  """
  @spec term_for(module() | map(), String.t()) :: String.t() | nil
  def term_for(domain_or_dsl, word) when is_binary(word) do
    if spark_dsl?(domain_or_dsl) do
      case Spark.Dsl.Extension.get_persisted(
             domain_or_dsl,
             :ash_harness_terms_by_word
           ) do
        %{} = map ->
          Map.get(map, word)

        _ ->
          Enum.find_value(terms(domain_or_dsl), fn
            %Term{word: ^word, definition: d} -> d
            _ -> nil
          end)
      end
    else
      nil
    end
  end

  @doc """
  Returns `true` when the domain declares any agent-annotation content.
  """
  @spec agent_annotated?(module() | map()) :: boolean()
  def agent_annotated?(domain_or_dsl) do
    if spark_dsl?(domain_or_dsl) do
      case Spark.Dsl.Extension.get_persisted(
             domain_or_dsl,
             :ash_harness_domain_annotated?
           ) do
        true -> true
        _ -> false
      end
    else
      false
    end
  end

  defp spark_dsl?(map) when is_map(map), do: true
  defp spark_dsl?(%_{}), do: true

  defp spark_dsl?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0)
  end

  defp spark_dsl?(_), do: false
end
