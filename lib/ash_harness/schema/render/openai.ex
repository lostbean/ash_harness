defmodule AshHarness.Schema.Render.OpenAI do
  @moduledoc """
  Renders an `AshHarness.Schema.Canonical` struct into the OpenAI tools
  shape:

      %{
        "type" => "function",
        "function" => %{
          "name" => "...",
          "description" => "...",
          "parameters" => %{
            "type" => "object",
            "properties" => %{...},
            "required" => [...]
          }
        }
      }
  """

  alias AshHarness.Schema.Canonical
  alias AshHarness.Schema.Render.JSONSchema

  @spec render(Canonical.t()) :: %{required(String.t()) => any()}
  def render(%Canonical{} = canonical) do
    %{
      "type" => "function",
      "function" => %{
        "name" => canonical.tool_name,
        "description" => canonical.description,
        "parameters" => %{
          "type" => "object",
          "properties" => JSONSchema.properties(canonical.parameters),
          "required" => Enum.map(canonical.required, &Atom.to_string/1)
        }
      }
    }
  end
end
