defmodule AshHarness.ToolGen do
  @moduledoc """
  Compile-time emission of `Jido.Action` modules and helpers for
  building `Jido.Composer.Skill` values. Triggered by the
  `AshHarness.Agent.Transformers.EmitTools` transformer.

  See `AshHarness.ToolGen.ActionModule` and
  `AshHarness.ToolGen.SkillModule` for the emitters.
  """

  alias AshHarness.Schema.Canonical
  alias AshHarness.Schema.ParamSpec

  @doc """
  Builds a NimbleOptions-style schema keyword list from a canonical
  param map. Used by the generated `use Jido.Action, schema: [...]`.
  """
  @spec nimble_schema(Canonical.t()) :: keyword()
  def nimble_schema(%Canonical{parameters: params, required: required}) do
    required_set = MapSet.new(required)

    params
    |> Enum.map(fn {name, %ParamSpec{} = spec} ->
      {name, param_spec_to_nimble(spec, MapSet.member?(required_set, name))}
    end)
  end

  defp param_spec_to_nimble(%ParamSpec{type: type, description: desc, enum: enum}, required?) do
    base = [type: nimble_type(type, enum)]

    base = if required?, do: [{:required, true} | base], else: base
    if desc, do: [{:doc, desc} | base], else: base
  end

  defp nimble_type(:string, _), do: :string
  defp nimble_type(:integer, _), do: :integer
  defp nimble_type(:float, _), do: :float
  defp nimble_type(:boolean, _), do: :boolean
  defp nimble_type(:enum, _), do: :string
  defp nimble_type(:object, _), do: :map
  defp nimble_type(:array, _), do: {:list, :any}
  defp nimble_type(_, _), do: :any

  @doc """
  Build the module name of the generated Jido.Action for a canonical.
  """
  @spec action_module(module(), Canonical.t()) :: module()
  def action_module(agent_module, %Canonical{} = canonical) do
    short = resource_short(canonical.resource)
    action = Atom.to_string(canonical.action_name) |> Macro.camelize()
    Module.concat([agent_module, Tools, Macro.camelize(short), action])
  end

  @doc """
  Build the module name of the generated Skill helper for a resource.
  """
  @spec skill_module(module(), module()) :: module()
  def skill_module(agent_module, resource_module) do
    short = resource_short(resource_module)
    Module.concat([agent_module, Skills, Macro.camelize(short)])
  end

  defp resource_short(resource_module) do
    AshHarness.Schema.resource_short_name(resource_module)
  end
end
