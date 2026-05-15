defmodule AshHarness.Errors.ValidationFailed do
  @moduledoc """
  Returned (wrapped in `{:error, _}`) when the action executor catches
  an `Ash.Error.Invalid` — typically a changeset/input validation
  failure. Splode class: `:validation`.

  Carries the original `Ash.Error.Invalid` in `:ash_error` so the
  repair formatter can render per-field bullet lines.
  """

  @type t :: %__MODULE__{
          agent: module() | nil,
          resource: module() | nil,
          action: atom() | nil,
          ash_error: Ash.Error.Invalid.t() | nil
        }

  defexception [:agent, :resource, :action, :ash_error]

  @impl true
  def message(%__MODULE__{resource: resource, action: action}) do
    "validation failed for #{inspect(resource)}.#{inspect(action)}"
  end
end
