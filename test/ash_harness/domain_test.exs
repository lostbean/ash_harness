defmodule AshHarness.DomainTest do
  use ExUnit.Case, async: true
  require Spark.Test

  alias AshHarness.Domain.Info
  alias AshHarness.Domain.Term
  alias AshHarness.Test.Domain

  test "description/1 returns declared description" do
    assert Info.description(Domain) ==
             "Test ticketing domain used by the AshHarness suite."
  end

  test "terms/1 returns Term structs" do
    terms = Info.terms(Domain)
    assert length(terms) == 2
    assert Enum.all?(terms, &match?(%Term{}, &1))
  end

  test "term_for/2 looks up by word" do
    assert Info.term_for(Domain, "ticket") ==
             "A unit of work in the support queue."
  end

  test "term_for/2 returns nil for missing word" do
    assert Info.term_for(Domain, "nonexistent") == nil
  end

  test "agent_annotated?/1 reflects declaration" do
    assert Info.agent_annotated?(Domain)
  end

  test "duplicate term word fails to compile" do
    errors =
      Spark.Test.dsl_errors do
        defmodule Elixir.AshHarness.DomainTest.DupTerms do
          use Ash.Domain,
            extensions: [AshHarness.Domain],
            validate_config_inclusion?: false

          agent_domain do
            term("x", "first")
            term("x", "second")
          end

          resources do
          end
        end
      end

    assert Enum.any?(errors, fn {_mod, errs} ->
             Enum.any?(errs, fn e ->
               Exception.message(e) =~ ~s|term "x" more than once|
             end)
           end)
  end
end
