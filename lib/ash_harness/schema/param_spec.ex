defmodule AshHarness.Schema.ParamSpec do
  @moduledoc """
  One parameter on a canonical tool schema.

  `:type` is the canonical tag used by `AshHarness.Schema.Render.*`:

    * `:string`, `:integer`, `:float`, `:boolean`
    * `:enum` (with `:enum` set to the allowed string values)
    * `:object` (free-form map / keyword list)
    * `:array` (with `:item_type` set to a recursive `ParamSpec`)

  `:format` carries a JSON-Schema `format` hint when relevant
  (`"uuid"`, `"date-time"`, `"date"`, `"time"`).
  """

  defstruct [
    :name,
    :type,
    :description,
    :enum,
    :format,
    :item_type
  ]

  @type type_tag ::
          :string
          | :integer
          | :float
          | :boolean
          | :enum
          | :object
          | :array

  @type t :: %__MODULE__{
          name: atom(),
          type: type_tag(),
          description: String.t() | nil,
          enum: [String.t()] | nil,
          format: String.t() | nil,
          item_type: t() | nil
        }
end
