defmodule AshHarness.ResourceTest do
  use ExUnit.Case, async: true

  alias AshHarness.Resource.Hint
  alias AshHarness.Resource.Info
  alias AshHarness.Test.Project
  alias AshHarness.Test.Ticket

  describe "agent_annotated?" do
    test "true for resources that declare agent_annotations" do
      assert Info.agent_annotated?(Ticket)
      assert Info.agent_annotated?(Project)
    end

    test "false for non-AshHarness modules" do
      refute Info.agent_annotated?(__MODULE__)
    end
  end

  describe "description/1" do
    test "returns the declared description" do
      assert Info.description(Ticket) == "A unit of work in the support queue."
    end

    test "returns nil for unannotated modules" do
      assert Info.description(__MODULE__) == nil
    end
  end

  describe "traversable/1" do
    test "returns the declared list" do
      assert Enum.sort(Info.traversable(Ticket)) ==
               Enum.sort([:project, :comments, :parent_ticket])
    end

    test "returns [] for resources that don't declare traversable" do
      assert Info.traversable(AshHarness.Test.Member) == []
    end

    test "returns [] for unannotated modules" do
      assert Info.traversable(__MODULE__) == []
    end
  end

  describe "hidden_attributes/1" do
    test "returns the declared list" do
      assert Info.hidden_attributes(Ticket) == [:internal_notes]
    end

    test "returns [] when not declared" do
      assert Info.hidden_attributes(Project) == []
    end
  end

  describe "hints/1 and hint_for/2" do
    test "returns hint structs" do
      assert [%Hint{} | _] = Info.hints(Ticket)
    end

    test "looks up by action name" do
      assert Info.hint_for(Ticket, :assign) ==
               "Use this to delegate the ticket to a teammate."

      assert Info.hint_for(Ticket, :resolve) ==
               "Only valid when status is :in_progress."
    end

    test "returns nil for missing hint" do
      assert Info.hint_for(Ticket, :nonexistent) == nil
    end
  end

  describe "compile-time validation" do
    import Spark.Test

    test "fails when hint references unknown action" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.ResourceTest.BadHint do
            use Ash.Resource,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshHarness.Resource]

            agent_annotations do
              description("broken")
              hint(:foo, "no such action")
            end

            ets do
              private?(true)
            end

            attributes do
              uuid_primary_key(:id)
            end

            actions do
              defaults([:read])
            end
          end
        end

      assert Enum.any?(errors, fn {_mod, errs} ->
               Enum.any?(errs, fn e -> Exception.message(e) =~ "unknown action :foo" end)
             end)
    end

    test "fails when traversable references unknown relationship" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.ResourceTest.BadTraversable do
            use Ash.Resource,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshHarness.Resource]

            agent_annotations do
              description("broken")
              traversable([:bar])
            end

            ets do
              private?(true)
            end

            attributes do
              uuid_primary_key(:id)
            end

            actions do
              defaults([:read])
            end
          end
        end

      assert Enum.any?(errors, fn {_mod, errs} ->
               Enum.any?(errs, fn e ->
                 Exception.message(e) =~ "unknown relationship :bar"
               end)
             end)
    end

    test "fails when hidden_attributes references unknown attribute" do
      errors =
        dsl_errors do
          defmodule Elixir.AshHarness.ResourceTest.BadHidden do
            use Ash.Resource,
              data_layer: Ash.DataLayer.Ets,
              extensions: [AshHarness.Resource]

            agent_annotations do
              description("broken")
              hidden_attributes([:baz])
            end

            ets do
              private?(true)
            end

            attributes do
              uuid_primary_key(:id)
            end

            actions do
              defaults([:read])
            end
          end
        end

      assert Enum.any?(errors, fn {_mod, errs} ->
               Enum.any?(errs, fn e ->
                 Exception.message(e) =~ "unknown attribute :baz"
               end)
             end)
    end
  end
end
