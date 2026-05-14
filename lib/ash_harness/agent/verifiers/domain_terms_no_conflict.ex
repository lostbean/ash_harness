defmodule AshHarness.Agent.Verifiers.DomainTermsNoConflict do
  @moduledoc """
  No two domains in the agent's `domains:` list may declare the same
  term `word`.
  """

  use Spark.Dsl.Verifier

  alias AshHarness.Domain.Info, as: DomainInfo
  alias Spark.Dsl.Verifier
  alias Spark.Error.DslError

  @impl true
  def verify(dsl_state) do
    module = Verifier.get_persisted(dsl_state, :module)
    domains = Verifier.get_persisted(dsl_state, :ash_harness_domains, [])

    word_to_domains =
      Enum.reduce(domains, %{}, fn domain, acc ->
        terms = DomainInfo.terms(domain)

        Enum.reduce(terms, acc, fn %{word: word}, inner ->
          Map.update(inner, word, [domain], fn existing -> [domain | existing] end)
        end)
      end)

    duplicates =
      word_to_domains
      |> Enum.filter(fn {_word, ds} -> length(Enum.uniq(ds)) > 1 end)
      |> Enum.map(fn {word, ds} -> {word, Enum.uniq(ds)} end)

    case duplicates do
      [] ->
        :ok

      [{word, domains_list} | _] ->
        {:error,
         DslError.exception(
           module: module,
           path: [],
           message:
             "two domains in agent #{inspect(module)}'s `domains:` list both " <>
               "define term \"#{word}\": #{inspect(domains_list)}"
         )}
    end
  end
end
