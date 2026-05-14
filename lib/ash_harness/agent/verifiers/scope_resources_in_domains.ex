defmodule AshHarness.Agent.Verifiers.ScopeResourcesInDomains do
  @moduledoc """
  Every scoped resource must belong to a domain in the agent's
  `domains:` list.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Agent.Scope.ResourceEntry
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)

    domains =
      Verifier.get_persisted(dsl_state, :ash_harness_domains, [])
      |> MapSet.new()

    entries = Verifier.get_entities(dsl_state, [:scope])

    Enum.reduce_while(entries, :ok, fn %ResourceEntry{module: resource}, :ok ->
      case resource_domain(resource) do
        nil ->
          {:halt,
           {:error,
            DslError.exception(
              module: module,
              path: [:scope, :resource],
              message:
                "scoped resource #{inspect(resource)} has no Ash domain; cannot validate against agent's `domains:` list"
            )}}

        domain ->
          if MapSet.member?(domains, domain) do
            {:cont, :ok}
          else
            {:halt,
             {:error,
              DslError.exception(
                module: module,
                path: [:scope, :resource],
                message:
                  "scoped resource #{inspect(resource)} belongs to domain " <>
                    "#{inspect(domain)}, which is not listed in the agent's " <>
                    "`domains:` option (#{inspect(MapSet.to_list(domains))})"
              )}}
          end
      end
    end)
  end

  defp resource_domain(resource) do
    if function_exported?(Ash.Resource.Info, :domain, 1) do
      Ash.Resource.Info.domain(resource)
    else
      nil
    end
  end
end
