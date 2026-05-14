defmodule AshHarness.Schema.Render.MCP do
  @moduledoc """
  Renders an `AshHarness.Schema.Canonical` struct into the MCP tool
  shape:

      %{
        "name" => "...",
        "description" => "...",
        "inputSchema" => %{
          "type" => "object",
          "properties" => %{...},
          "required" => [...]
        }
      }
  """

  alias AshHarness.Schema.Canonical
  alias AshHarness.Schema.Render.JSONSchema

  @spec render(Canonical.t()) :: %{required(String.t()) => any()}
  def render(%Canonical{} = canonical) do
    %{
      "name" => canonical.tool_name,
      "description" => canonical.description,
      "inputSchema" => %{
        "type" => "object",
        "properties" => JSONSchema.properties(canonical.parameters),
        "required" => Enum.map(canonical.required, &Atom.to_string/1)
      }
    }
  end
end
