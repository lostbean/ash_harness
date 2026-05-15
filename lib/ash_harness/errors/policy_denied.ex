defmodule AshHarness.Errors.PolicyDenied do
  @moduledoc """
  Raised (or returned wrapped in `{:error, _}`) when `Ash.can?/2`
  returns `false` for a mutating action, or when the action executor
  catches an `Ash.Error.Forbidden`. Splode class: `:policy`.

  Carries the original `Ash.Error.Forbidden` in `:ash_error` for
  downstream formatting and telemetry encoding.
  """

  @type t :: %__MODULE__{
          agent: module() | nil,
          resource: module() | nil,
          action: atom() | nil,
          actor: any() | nil,
          ash_error: Ash.Error.Forbidden.t() | nil
        }

  defexception [:agent, :resource, :action, :actor, :ash_error]

  @impl true
  def message(%__MODULE__{agent: agent, resource: resource, action: action}) do
    "policy denied: #{inspect(agent)} forbidden from " <>
      "#{inspect(resource)}.#{inspect(action)}"
  end
end
