defmodule AshHarness.Schema.Canonical do
  @moduledoc """
  Provider-neutral tool schema artifact derived once at agent compile
  time per scoped (resource, action) pair. Renderers under
  `AshHarness.Schema.Render.*` project this struct into provider-specific
  shapes.
  """

  defstruct [
    :resource,
    :action_name,
    :action_type,
    :tool_name,
    :description,
    parameters: %{},
    required: [],
    examples: []
  ]

  @type t :: %__MODULE__{
          resource: module(),
          action_name: atom(),
          action_type: :read | :create | :update | :destroy | :action | nil,
          tool_name: String.t(),
          description: String.t(),
          parameters: %{atom() => AshHarness.Schema.ParamSpec.t()},
          required: [atom()],
          examples: list()
        }
end
