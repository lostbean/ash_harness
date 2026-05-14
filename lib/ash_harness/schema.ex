defmodule AshHarness.Schema do
  @moduledoc """
  Canonical schema derivation for AshHarness tools. The canonical form
  is a single, provider-neutral struct (`AshHarness.Schema.Canonical`)
  derived once from an Ash action and then rendered to provider-specific
  shapes (Anthropic, OpenAI, MCP) by pure renderer modules under
  `AshHarness.Schema.Render.*`.
  """

  alias AshHarness.Resource.Info, as: ResourceInfo
  alias AshHarness.Schema.AshTypeMapper
  alias AshHarness.Schema.Canonical
  alias AshHarness.Schema.ParamSpec

  @doc """
  Builds an `AshHarness.Schema.Canonical` struct for the given resource
  and action name. Used at compile time by
  `AshHarness.Agent.Transformers.ComputeToolSet`.
  """
  @spec canonical_for(module(), atom()) :: Canonical.t()
  def canonical_for(resource, action_name)
      when is_atom(resource) and is_atom(action_name) do
    action = Ash.Resource.Info.action(resource, action_name)
    {parameters, required} = build_parameters(resource, action)

    %Canonical{
      resource: resource,
      action_name: action_name,
      action_type: action && action.type,
      tool_name: tool_name(resource, action_name),
      description: tool_description(resource, action_name, action),
      parameters: parameters,
      required: required,
      examples: []
    }
  end

  @doc """
  Returns the snake-cased last segment of a resource module name joined
  with the action atom.

      iex> AshHarness.Schema.tool_name(MyApp.Ticketing.Ticket, :assign)
      "ticket__assign"
  """
  @spec tool_name(module(), atom()) :: String.t()
  def tool_name(resource, action_name) when is_atom(resource) and is_atom(action_name) do
    "#{resource_short_name(resource)}__#{action_name}"
  end

  @doc """
  Returns the snake-cased last segment of the resource module name
  (e.g., `MyApp.Ticketing.Ticket` -> `"ticket"`).
  """
  @spec resource_short_name(module()) :: String.t()
  def resource_short_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp tool_description(resource, action_name, _action) do
    base = ResourceInfo.description(resource) || "#{inspect(resource)}"
    hint = ResourceInfo.hint_for(resource, action_name)

    if hint && byte_size(hint) > 0 do
      "#{base} — #{hint}"
    else
      "#{base} (action: #{action_name})"
    end
  end

  defp build_parameters(_resource, nil), do: {%{}, []}

  defp build_parameters(resource, action) do
    hidden = MapSet.new(ResourceInfo.hidden_attributes(resource))
    accept = action_accept(resource, action)
    arguments = action.arguments || []

    accept_specs =
      accept
      |> Enum.reject(&MapSet.member?(hidden, &1))
      |> Enum.map(fn name ->
        attribute = Ash.Resource.Info.attribute(resource, name)
        attribute_to_param_spec(name, attribute)
      end)
      |> Enum.reject(&is_nil/1)

    argument_specs =
      Enum.map(arguments, &argument_to_param_spec/1)

    base_specs = accept_specs ++ argument_specs

    specs =
      case action.type do
        :update -> [id_param() | base_specs]
        :destroy -> [id_param() | base_specs]
        _ -> base_specs
      end

    parameters =
      Enum.into(specs, %{}, fn %ParamSpec{name: name} = spec -> {name, spec} end)

    required_set =
      MapSet.union(
        MapSet.new(required_accepts(resource, action, accept, hidden)),
        MapSet.new(required_arguments(arguments))
      )

    required_with_id =
      case action.type do
        :update -> [:id | MapSet.to_list(required_set)] |> Enum.uniq()
        :destroy -> [:id | MapSet.to_list(required_set)] |> Enum.uniq()
        _ -> MapSet.to_list(required_set)
      end

    {parameters, required_with_id}
  end

  defp action_accept(resource, %{type: :read}), do: read_accept(resource)
  defp action_accept(_resource, %{accept: accept}) when is_list(accept), do: accept
  defp action_accept(_resource, _action), do: []

  defp read_accept(_resource), do: []

  defp required_accepts(_resource, %{type: :read}, _accept, _hidden), do: []

  defp required_accepts(resource, %{type: :create}, accept, hidden) do
    Enum.filter(accept, fn name ->
      not MapSet.member?(hidden, name) and
        case Ash.Resource.Info.attribute(resource, name) do
          %{allow_nil?: false, default: nil, generated?: false} -> true
          _ -> false
        end
    end)
  end

  defp required_accepts(_resource, _action, _accept, _hidden), do: []

  defp required_arguments(arguments) do
    arguments
    |> Enum.filter(fn arg -> not arg.allow_nil? end)
    |> Enum.map(& &1.name)
  end

  defp attribute_to_param_spec(_name, nil), do: nil

  defp attribute_to_param_spec(name, %{type: type, constraints: constraints}) do
    AshTypeMapper.to_param_spec(name, type, constraints)
  end

  defp argument_to_param_spec(%{name: name, type: type, constraints: constraints}) do
    AshTypeMapper.to_param_spec(name, type, constraints)
  end

  defp id_param do
    %ParamSpec{
      name: :id,
      type: :string,
      description: "ID of the record to operate on.",
      enum: nil,
      format: "uuid",
      item_type: nil
    }
  end
end
