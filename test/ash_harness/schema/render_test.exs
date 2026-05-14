defmodule AshHarness.Schema.RenderTest do
  use ExUnit.Case, async: true

  alias AshHarness.Schema
  alias AshHarness.Schema.Render
  alias AshHarness.Test.Ticket

  setup do
    %{canonical: Schema.canonical_for(Ticket, :assign)}
  end

  describe "Anthropic" do
    test "renders the Anthropic shape", %{canonical: canonical} do
      out = Render.Anthropic.render(canonical)
      assert out["name"] == "ticket__assign"
      assert is_binary(out["description"])
      assert out["input_schema"]["type"] == "object"
      assert is_map(out["input_schema"]["properties"])
      assert is_list(out["input_schema"]["required"])
    end

    test "is pure", %{canonical: canonical} do
      assert Render.Anthropic.render(canonical) == Render.Anthropic.render(canonical)
    end

    test "id required has format uuid", %{canonical: canonical} do
      out = Render.Anthropic.render(canonical)
      assert out["input_schema"]["properties"]["id"]["format"] == "uuid"
    end
  end

  describe "OpenAI" do
    test "renders the OpenAI tools shape", %{canonical: canonical} do
      out = Render.OpenAI.render(canonical)
      assert out["type"] == "function"
      assert out["function"]["name"] == "ticket__assign"
      assert out["function"]["parameters"]["type"] == "object"
    end

    test "is pure", %{canonical: canonical} do
      assert Render.OpenAI.render(canonical) == Render.OpenAI.render(canonical)
    end
  end

  describe "MCP" do
    test "renders the MCP shape", %{canonical: canonical} do
      out = Render.MCP.render(canonical)
      assert out["name"] == "ticket__assign"
      assert out["inputSchema"]["type"] == "object"
    end

    test "is pure", %{canonical: canonical} do
      assert Render.MCP.render(canonical) == Render.MCP.render(canonical)
    end
  end

  test "enum attribute renders as enum on Anthropic" do
    canonical = Schema.canonical_for(Ticket, :open_ticket)
    out = Render.Anthropic.render(canonical)
    priority = out["input_schema"]["properties"]["priority"]
    assert priority["type"] == "string"
    assert Enum.sort(priority["enum"]) == ["high", "low", "medium"]
  end
end
