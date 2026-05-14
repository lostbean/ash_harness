defmodule AshHarness.Schema.Render.JSONSchema do
  @moduledoc """
  Shared helpers that turn `AshHarness.Schema.ParamSpec` values into
  JSON-Schema property maps. Used by `AshHarness.Schema.Render.{Anthropic,
  OpenAI, MCP}`.
  """

  alias AshHarness.Schema.ParamSpec

  @spec properties(%{atom() => ParamSpec.t()}) :: %{required(String.t()) => any()}
  def properties(parameters) when is_map(parameters) do
    Enum.into(parameters, %{}, fn {name, spec} ->
      {Atom.to_string(name), to_property(spec)}
    end)
  end

  @spec to_property(ParamSpec.t()) :: %{required(String.t()) => any()}
  def to_property(%ParamSpec{} = spec) do
    base = %{"type" => json_type(spec.type)}

    base
    |> maybe_put("description", spec.description)
    |> maybe_put("format", spec.format)
    |> maybe_put_enum(spec)
    |> maybe_put_items(spec)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_enum(map, %ParamSpec{type: :enum, enum: enum}) when is_list(enum) do
    Map.put(map, "enum", enum)
  end

  defp maybe_put_enum(map, _), do: map

  defp maybe_put_items(map, %ParamSpec{type: :array, item_type: %ParamSpec{} = inner}) do
    Map.put(map, "items", to_property(inner))
  end

  defp maybe_put_items(map, _), do: map

  defp json_type(:string), do: "string"
  defp json_type(:integer), do: "integer"
  defp json_type(:float), do: "number"
  defp json_type(:boolean), do: "boolean"
  defp json_type(:enum), do: "string"
  defp json_type(:object), do: "object"
  defp json_type(:array), do: "array"
end
