defmodule AshHarness.Schema.AshTypeMapperTest do
  use ExUnit.Case, async: true

  alias AshHarness.Schema.AshTypeMapper, as: Mapper
  alias AshHarness.Schema.ParamSpec

  test ":string -> :string" do
    assert %ParamSpec{type: :string} = Mapper.to_param_spec(:x, :string, [])
  end

  test ":integer -> :integer" do
    assert %ParamSpec{type: :integer} = Mapper.to_param_spec(:x, :integer, [])
  end

  test ":float -> :float" do
    assert %ParamSpec{type: :float} = Mapper.to_param_spec(:x, :float, [])
  end

  test ":boolean -> :boolean" do
    assert %ParamSpec{type: :boolean} = Mapper.to_param_spec(:x, :boolean, [])
  end

  test ":uuid -> string with format uuid" do
    assert %ParamSpec{type: :string, format: "uuid"} =
             Mapper.to_param_spec(:x, :uuid, [])
  end

  test ":atom with one_of -> :enum" do
    spec = Mapper.to_param_spec(:x, :atom, one_of: [:open, :closed])
    assert spec.type == :enum
    assert spec.enum == ["open", "closed"]
  end

  test ":atom without one_of -> :string" do
    spec = Mapper.to_param_spec(:x, :atom, [])
    assert spec.type == :string
    assert spec.enum == nil
  end

  test ":utc_datetime -> string with format date-time" do
    assert %ParamSpec{type: :string, format: "date-time"} =
             Mapper.to_param_spec(:x, :utc_datetime, [])
  end

  test ":date -> string with format date" do
    assert %ParamSpec{type: :string, format: "date"} =
             Mapper.to_param_spec(:x, :date, [])
  end

  test ":time -> string with format time" do
    assert %ParamSpec{type: :string, format: "time"} =
             Mapper.to_param_spec(:x, :time, [])
  end

  test ":decimal -> string with format decimal" do
    assert %ParamSpec{type: :string, format: "decimal"} =
             Mapper.to_param_spec(:x, :decimal, [])
  end

  test ":map -> :object" do
    assert %ParamSpec{type: :object} = Mapper.to_param_spec(:x, :map, [])
  end

  test "{:array, :string} -> :array with string item_type" do
    spec = Mapper.to_param_spec(:x, {:array, :string}, [])
    assert spec.type == :array
    assert spec.item_type.type == :string
  end

  test "{:array, :integer}" do
    spec = Mapper.to_param_spec(:x, {:array, :integer}, [])
    assert spec.type == :array
    assert spec.item_type.type == :integer
  end
end
