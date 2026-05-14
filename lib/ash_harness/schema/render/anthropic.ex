defmodule AshHarness.Schema.Render.Anthropic do
  @moduledoc """
  Renders an `AshHarness.Schema.Canonical` struct into the Anthropic
  Messages API tool shape:

      %{
        "name" => "...",
        "description" => "...",
        "input_schema" => %{
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
      "input_schema" => %{
        "type" => "object",
        "properties" => JSONSchema.properties(canonical.parameters),
        "required" => Enum.map(canonical.required, &Atom.to_string/1)
      }
    }
  end
end
