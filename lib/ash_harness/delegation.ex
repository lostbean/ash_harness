defmodule AshHarness.Delegation do
  @moduledoc """
  Cross-agent delegation. The caller's `delegates_to` section lists
  allowed targets; depth is capped (default 3); the delegate runs in a
  fresh session with its own actor; the reply is a text string only.

  See `design/layers/09-delegation.md` (and ADR 0004) for the rationale
  behind the text-only return shape.

  The implementation lives in `AshHarness.Delegation.Initiate`; this
  module is a thin re-export wrapper that preserves the public
  `AshHarness.Delegation.initiate/4` contract for v0.1.2.

  Refusals return `%AshHarness.Errors.DelegationNotPermitted{}` or
  `%AshHarness.Errors.DelegationDepthExceeded{}` (v0.1.2 struct-error
  contract).
  """

  alias AshHarness.Delegation.Initiate
  alias AshHarness.Errors.DelegationDepthExceeded
  alias AshHarness.Errors.DelegationNotPermitted
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.TrajectoryEntry

  @doc """
  Initiate a delegation. Returns:
    * `{:ok, reply_text, updated_caller_session, delegate_trajectory}`
    * `{:error, %AshHarness.Errors.DelegationNotPermitted{}}`
    * `{:error, %AshHarness.Errors.DelegationDepthExceeded{}}`
    * `{:error, :delegate_halted}` when the child suspended on its
      own confirmation gate (v0.1.2 nested-HITL deferral; the parent
      session does NOT see the child's `ApprovalRequest`)
    * `{:error, term()}` for downstream delegate failures

  ## Options
    * `:max_depth` — overrides the configured cap.
    * `:request_id` — correlate caller's dispatch with delegation
      telemetry; defaults to a fresh UUID v4 when absent.
  """
  @spec initiate(Session.t(), module(), String.t(), keyword()) ::
          {:ok, String.t(), Session.t(), [TrajectoryEntry.t()]}
          | {:error, :delegate_halted}
          | {:error, DelegationNotPermitted.t()}
          | {:error, DelegationDepthExceeded.t()}
          | {:error, term()}
  defdelegate initiate(caller_session, target, question, opts \\ []), to: Initiate, as: :run
end
