defmodule AshHarness.Harness.Result do
  @moduledoc """
  The outcome of dispatching one tool call through the harness.
  `:status` is one of `:ok`, `:error`, `:scope_violation`,
  `:reasoning_required`, `:confirmation_required`,
  `:budget_exceeded`, `:policy_denied`.
  """

  defstruct [
    :status,
    :intent,
    :data,
    :error,
    :changeset_errors,
    :duration_ms
  ]

  @type status ::
          :ok
          | :error
          | :scope_violation
          | :reasoning_required
          | :confirmation_required
          | :budget_exceeded
          | :policy_denied

  @type t :: %__MODULE__{
          status: status(),
          intent: AshHarness.Harness.Intent.t() | nil,
          data: any(),
          error: any(),
          changeset_errors: [%{field: atom(), message: String.t()}] | nil,
          duration_ms: non_neg_integer() | nil
        }
end
