defmodule AshHarness.Schema.CanonicalTest do
  use ExUnit.Case, async: true

  alias AshHarness.Schema
  alias AshHarness.Schema.Canonical
  alias AshHarness.Test.Ticket

  test "tool_name combines snake-cased resource short name with action" do
    assert Schema.tool_name(Ticket, :assign) == "ticket__assign"
    assert Schema.tool_name(Ticket, :open_ticket) == "ticket__open_ticket"
    assert Schema.tool_name(AshHarness.Test.Order, :read) == "order__read"
  end

  test "canonical_for/2 returns a Canonical struct" do
    assert %Canonical{} = canonical = Schema.canonical_for(Ticket, :read)
    assert canonical.tool_name == "ticket__read"
    assert canonical.action_name == :read
    assert canonical.resource == Ticket
    assert canonical.action_type == :read
  end

  test "description includes action hint when one is declared" do
    canonical = Schema.canonical_for(Ticket, :assign)
    assert canonical.description =~ "Use this to delegate"
  end

  test "create-action canonical lists required fields" do
    canonical = Schema.canonical_for(Ticket, :open_ticket)
    assert :title in canonical.required
    refute :id in canonical.required
  end

  test "update-action canonical includes :id as required" do
    canonical = Schema.canonical_for(Ticket, :assign)
    assert :id in canonical.required
  end

  test "destroy-action canonical includes :id" do
    canonical = Schema.canonical_for(Ticket, :destroy)
    assert :id in canonical.required
  end

  test "hidden attributes are excluded from parameters" do
    canonical = Schema.canonical_for(Ticket, :assign)
    refute Map.has_key?(canonical.parameters, :internal_notes)
  end
end
