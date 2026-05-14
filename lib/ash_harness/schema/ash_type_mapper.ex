defmodule AshHarness.Schema.AshTypeMapper do
  @moduledoc """
  Maps Ash attribute / argument types to canonical
  `AshHarness.Schema.ParamSpec` values.

  Supported types: `:string`, `:integer`, `:float`, `:boolean`,
  `:uuid`, `:atom` with `one_of`, `:utc_datetime`,
  `:utc_datetime_usec`, `:date`, `:time`, `:decimal`, `:map`,
  `:keyword_list`, `{:array, inner}`, and embedded resources (mapped
  recursively to `:object`).
  """

  alias AshHarness.Schema.ParamSpec

  @doc """
  Builds a `%ParamSpec{}` from a name, an Ash type, and constraints.
  """
  @spec to_param_spec(atom(), term(), keyword()) :: ParamSpec.t()
  def to_param_spec(name, type, constraints) when is_atom(name) do
    {tag, format, enum, item_type} = classify(type, constraints)

    %ParamSpec{
      name: name,
      type: tag,
      description: nil,
      enum: enum,
      format: format,
      item_type: item_type
    }
  end

  defp classify({:array, inner}, constraints) do
    item_constraints =
      case constraints[:items] do
        c when is_list(c) -> c
        _ -> []
      end

    item_spec = to_param_spec(:_item, inner, item_constraints)
    {:array, nil, nil, item_spec}
  end

  defp classify(:string, _), do: {:string, nil, nil, nil}
  defp classify(Ash.Type.String, _), do: {:string, nil, nil, nil}
  defp classify(:integer, _), do: {:integer, nil, nil, nil}
  defp classify(Ash.Type.Integer, _), do: {:integer, nil, nil, nil}
  defp classify(:float, _), do: {:float, nil, nil, nil}
  defp classify(Ash.Type.Float, _), do: {:float, nil, nil, nil}
  defp classify(:boolean, _), do: {:boolean, nil, nil, nil}
  defp classify(Ash.Type.Boolean, _), do: {:boolean, nil, nil, nil}
  defp classify(:uuid, _), do: {:string, "uuid", nil, nil}
  defp classify(Ash.Type.UUID, _), do: {:string, "uuid", nil, nil}
  defp classify(Ash.Type.UUIDv7, _), do: {:string, "uuid", nil, nil}

  defp classify(:atom, constraints), do: classify_atom(constraints)
  defp classify(Ash.Type.Atom, constraints), do: classify_atom(constraints)
  defp classify(:utc_datetime, _), do: {:string, "date-time", nil, nil}
  defp classify(Ash.Type.UtcDatetime, _), do: {:string, "date-time", nil, nil}
  defp classify(:utc_datetime_usec, _), do: {:string, "date-time", nil, nil}
  defp classify(Ash.Type.UtcDatetimeUsec, _), do: {:string, "date-time", nil, nil}
  defp classify(:date, _), do: {:string, "date", nil, nil}
  defp classify(Ash.Type.Date, _), do: {:string, "date", nil, nil}
  defp classify(:time, _), do: {:string, "time", nil, nil}
  defp classify(Ash.Type.Time, _), do: {:string, "time", nil, nil}
  defp classify(:decimal, _), do: {:string, "decimal", nil, nil}
  defp classify(Ash.Type.Decimal, _), do: {:string, "decimal", nil, nil}
  defp classify(:map, _), do: {:object, nil, nil, nil}
  defp classify(Ash.Type.Map, _), do: {:object, nil, nil, nil}
  defp classify(:keyword_list, _), do: {:object, nil, nil, nil}
  defp classify(Ash.Type.Keyword, _), do: {:object, nil, nil, nil}

  # Embedded resources / unknown — fall back to object.
  defp classify(_other, _constraints), do: {:object, nil, nil, nil}

  defp classify_atom(constraints) do
    case Keyword.get(constraints || [], :one_of) do
      list when is_list(list) and list != [] ->
        {:enum, nil, Enum.map(list, &Atom.to_string/1), nil}

      _ ->
        {:string, nil, nil, nil}
    end
  end
end
