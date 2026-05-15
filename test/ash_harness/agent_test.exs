defmodule AshHarness.AgentTest do
  use ExUnit.Case, async: true

  alias AshHarness.Agent.Behavior.Strategy
  alias AshHarness.Agent.Delegation.DelegateEntry
  alias AshHarness.Agent.Info
  alias AshHarness.Test.DelegatingAgent
  alias AshHarness.Test.ReadOnlyAgent
  alias AshHarness.Test.TriageAgent

  describe "identity" do
    test "exposes name/description/actor/model" do
      assert Info.name(TriageAgent) == "TriageBot"
      assert Info.description(TriageAgent) == "Triages incoming support tickets."
      assert Info.actor(TriageAgent) == %{id: "triage-bot", role: :bot}
      assert Info.model(TriageAgent) == "anthropic:claude-sonnet-4-5"
    end

    test "model is nil when not declared" do
      assert Info.model(ReadOnlyAgent) == nil
    end
  end

  describe "domains" do
    test "returns the list passed to use AshHarness.Agent" do
      assert Info.domains(TriageAgent) == [AshHarness.Test.Domain]
    end
  end

  describe "scope" do
    test "scoped_resources/1" do
      assert Enum.sort(Info.scoped_resources(TriageAgent)) ==
               Enum.sort([
                 AshHarness.Test.Ticket,
                 AshHarness.Test.Project,
                 AshHarness.Test.Member,
                 AshHarness.Test.Restricted
               ])
    end

    test "scoped_actions/2" do
      assert Enum.sort(Info.scoped_actions(TriageAgent, AshHarness.Test.Ticket)) ==
               Enum.sort([:read, :open_ticket, :assign])
    end

    test "in_scope?/3 true for declared, false for undeclared" do
      assert Info.in_scope?(TriageAgent, AshHarness.Test.Ticket, :assign)
      refute Info.in_scope?(TriageAgent, AshHarness.Test.Ticket, :destroy)
      refute Info.in_scope?(TriageAgent, AshHarness.Test.Comment, :read)
    end
  end

  describe "behavior" do
    test "confirm_before/auto_execute" do
      assert Info.confirm_before(TriageAgent) == [:assign]
      assert Enum.sort(Info.auto_execute(TriageAgent)) == Enum.sort([:read, :open_ticket])
    end

    test "confirms_action?/2" do
      assert Info.confirms_action?(TriageAgent, :assign)
      refute Info.confirms_action?(TriageAgent, :read)
    end

    test "strategies/1" do
      assert [%Strategy{name: :default}] = Info.strategies(TriageAgent)
    end
  end

  describe "delegates" do
    test "exposed via Info" do
      assert [%DelegateEntry{agent_module: TriageAgent, purpose: _, as: alias_name}] =
               Info.delegates(DelegatingAgent)

      assert is_binary(alias_name)
      assert Info.delegate_for?(DelegatingAgent, TriageAgent)
      refute Info.delegate_for?(DelegatingAgent, ReadOnlyAgent)
    end
  end

  describe "constraints" do
    test "returns declared values and defaults" do
      assert Info.max_mutations_per_turn(TriageAgent) == 5
      assert Info.require_reasoning_for(TriageAgent) == [:assign]
      assert Info.max_context_tokens(TriageAgent) == 128_000
      assert Info.max_repair_loop_retries(TriageAgent) == 3
    end

    test "defaults when no constraints block declared" do
      assert Info.max_mutations_per_turn(ReadOnlyAgent) == 10
      assert Info.max_context_tokens(ReadOnlyAgent) == 128_000
    end
  end

  describe "reasoning_required?/2" do
    test "true for actions in require_reasoning_for" do
      assert Info.reasoning_required?(TriageAgent, :assign)
      refute Info.reasoning_required?(TriageAgent, :read)
    end
  end

  describe "compile-time validation" do
    import Spark.Test

    defp has_dsl_error?(errors, regex) do
      Enum.any?(errors, fn {_mod, errs} ->
        Enum.any?(errs, fn e -> Exception.message(e) =~ regex end)
      end)
    end

    test "rejects empty scope" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.EmptyScopeAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
            end
          end
        end

      assert has_dsl_error?(errors, ~r/empty scope/)
    end

    test "rejects scope action that doesn't exist" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.BadActionAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:nonexistent])
              end
            end
          end
        end

      assert has_dsl_error?(errors, ~r/no such action exists/)
    end

    test "rejects confirm_before action that's not in scope" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.OutOfScopeConfirmAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end
            end

            behavior do
              confirm_before([:destroy])
            end
          end
        end

      assert has_dsl_error?(errors, ~r/confirm_before lists :destroy/)
    end

    test "rejects action declared both confirm_before and auto_execute" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.ConflictingPolicyAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end
            end

            behavior do
              confirm_before([:read])
              auto_execute([:read])
            end
          end
        end

      assert has_dsl_error?(errors, ~r/declares :read in both/)
    end

    test "rejects scoped resource not in declared domains" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.WrongDomainAgent do
            use AshHarness.Agent, domains: []

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end
            end
          end
        end

      assert has_dsl_error?(errors, ~r/not listed in the agent's `domains:`/)
    end

    test "rejects delegate target that's not an AshHarness agent" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.BadDelegateAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end
            end

            delegates_to do
              delegate(String, as: "string", purpose: "not an agent")
            end
          end
        end

      assert has_dsl_error?(errors, ~r/does not `use AshHarness\.Agent`/)
    end

    test "rejects two scoped resources whose short names collide" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.CollidingShortNamesAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end

              resource AshHarness.Test.Alt.Ticket do
                actions([:read])
              end
            end
          end
        end

      assert has_dsl_error?(errors, ~r/share the short name "ticket"/)
      assert has_dsl_error?(errors, ~r/Add `as: "<unique>"`/)
    end

    test "rejects delegate without an :as alias" do
      # The `:as` option is required at entity-build time, so the
      # absence is raised as a Spark.Error.DslError directly during
      # `delegate(...)` macro expansion (not via a verifier callback).
      err =
        assert_raise Spark.Error.DslError, fn ->
          defmodule Elixir.AshHarness.AgentTest.NoAliasDelegateAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end
            end

            delegates_to do
              delegate(AshHarness.Test.TriageAgent, purpose: "...")
            end
          end
        end

      assert Exception.message(err) =~ ~r/required :as option/i
    end

    test "rejects two delegates with the same alias (case-insensitive)" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.AgentTest.DupAliasDelegateAgent do
            use AshHarness.Agent, domains: [AshHarness.Test.Domain]

            identity do
              name("x")
              description("x")
              actor(%{})
            end

            scope do
              resource AshHarness.Test.Ticket do
                actions([:read])
              end
            end

            delegates_to do
              delegate(AshHarness.Test.TriageAgent, as: "billing", purpose: "...")
              delegate(AshHarness.Test.ReadOnlyAgent, as: "Billing", purpose: "...")
            end
          end
        end

      assert has_dsl_error?(errors, ~r/duplicate.*alias|alias.*"billing"/i)
    end
  end

  describe "delegate alias parsing" do
    test "delegate with as: sets the alias on DelegateEntry" do
      [entry] = Info.delegates(DelegatingAgent)
      assert entry.as == "triage"
    end
  end

  describe "persisted derived data" do
    test "reachability_graph/1 returns a map" do
      graph = Info.reachability_graph(TriageAgent)
      assert is_map(graph)
      assert Map.has_key?(graph, AshHarness.Test.Ticket)
    end

    test "tool_list/1 returns a list of canonical structs" do
      tools = Info.tool_list(TriageAgent)
      assert is_list(tools)
      assert length(tools) > 0
      assert Enum.all?(tools, &match?(%AshHarness.Schema.Canonical{}, &1))
    end
  end
end
