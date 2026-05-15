defmodule AshHarness.Errors do
  @moduledoc """
  Structured error types returned by AshHarness gates.

  Each error is a `defexception` struct that downstream code can
  pattern-match on. `classify/1` maps an error struct (or a wrapped
  `{:error, struct}` tuple) to a Splode-style class atom suitable for
  the OTel `error.class` attribute.

  The seven error structs are:

    * `AshHarness.Errors.ScopeViolation` — `:scope`
    * `AshHarness.Errors.PolicyDenied` — `:policy`
    * `AshHarness.Errors.ValidationFailed` — `:validation`
    * `AshHarness.Errors.MutationLimitExceeded` — `:budget`
    * `AshHarness.Errors.ReasoningRequired` — `:reasoning`
    * `AshHarness.Errors.DelegationNotPermitted` — `:delegation`
    * `AshHarness.Errors.DelegationDepthExceeded` — `:delegation`

  Gate returns moved from `{:error, atom()}` to `{:error, struct()}`
  in v0.1.2 to give the repair formatter, telemetry encoder, and host
  code a typed shape to dispatch on.
  """

  alias AshHarness.Errors.{
    DelegationDepthExceeded,
    DelegationNotPermitted,
    MutationLimitExceeded,
    PolicyDenied,
    ReasoningRequired,
    ScopeViolation,
    ValidationFailed
  }

  @type t ::
          ScopeViolation.t()
          | PolicyDenied.t()
          | ValidationFailed.t()
          | MutationLimitExceeded.t()
          | ReasoningRequired.t()
          | DelegationNotPermitted.t()
          | DelegationDepthExceeded.t()

  @type class :: :scope | :policy | :validation | :budget | :reasoning | :delegation

  @doc """
  Classify an error struct (or a wrapped `{:error, struct}` tuple) to
  a Splode-style class atom.

  Returns `:unknown` for terms we don't recognize so callers don't
  have to special-case nil/non-error values.
  """
  @spec classify(t() | {:error, t()} | term()) :: class() | :unknown
  def classify({:error, err}), do: classify(err)
  def classify(%ScopeViolation{}), do: :scope
  def classify(%PolicyDenied{}), do: :policy
  def classify(%ValidationFailed{}), do: :validation
  def classify(%MutationLimitExceeded{}), do: :budget
  def classify(%ReasoningRequired{}), do: :reasoning
  def classify(%DelegationNotPermitted{}), do: :delegation
  def classify(%DelegationDepthExceeded{}), do: :delegation
  def classify(_), do: :unknown
end
