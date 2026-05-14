defmodule AshHarness.Harness.ResumeUnitTest do
  @moduledoc """
  Unit-level coverage for `AshHarness.Harness.resume/2` against an
  orchestrator-strategy approval-gate suspension.

  Background:

  `Jido.Composer.Resume.deliver_resume/4` only matches suspensions in
  `strat.pending_suspension`, `strat.suspended_calls`, or
  `strat.fan_out`. The orchestrator strategy stores approval-gate
  suspensions in `strat.approval_gate.gated_calls` instead, so routing
  the resume signal through `Resume.resume/4` fails fast with
  `{:error, :no_matching_suspension}`.

  This test seeds an orchestrator agent with a gated call entry in
  `approval_gate.gated_calls` (matching the shape built by
  `ApprovalGate.gate_calls/2`) and confirms that `Harness.resume/2`
  does NOT bail out with `:no_matching_suspension`. The fix bypasses
  `Resume.resume/4` and dispatches `cmd(:suspend_resume, _)` directly,
  which the orchestrator strategy's resume clause handles correctly via
  `ApprovalGate.get/2`.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Harness
  alias AshHarness.Harness.OrchestratorFactory
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.RenderedContext
  alias AshHarness.Test.TriageAgent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Composer.ApprovalGate
  alias Jido.Composer.HITL.ApprovalRequest
  alias Jido.Composer.HITL.ApprovalResponse
  alias Jido.Composer.Suspension

  defp seed_orchestrator_with_gated_call do
    rendered = %RenderedContext{
      initial_text: "",
      resource_details: %{},
      token_estimate: 0,
      warnings: []
    }

    base = %Session{
      agent: TriageAgent,
      actor: %{id: "u"},
      model: nil,
      rendered_context: rendered,
      request_id: "req-resume-unit",
      metadata: %{},
      options: []
    }

    {:ok, agent} = OrchestratorFactory.build(base)

    request_id = "test-suspension-id"

    {:ok, request} =
      ApprovalRequest.new(
        id: request_id,
        prompt: "test approval",
        allowed_responses: [:approved, :rejected],
        metadata: %{tool_call_id: "tool_call_1", tool_name: "ticket__assign"}
      )

    # Match the shape `ApprovalGate.gate_calls/2` stores:
    # %{request_id => %{request: ApprovalRequest, call: tool_call_map}}.
    # `call` only needs `id`, `name`, `arguments` for the approval
    # decision path — `name` must be a registered node so
    # `build_tool_directive` can look it up if `:approved` is dispatched.
    fake_call = %{
      id: "tool_call_1",
      name: "ticket__assign",
      arguments: %{}
    }

    gated_entries = %{request_id => %{request: request, call: fake_call}}

    agent =
      StratState.update(agent, fn s ->
        new_ag = ApprovalGate.gate_calls(s.approval_gate, gated_entries)
        %{s | approval_gate: new_ag}
      end)

    {:ok, suspension} = Suspension.from_approval_request(request)

    {:ok, pid} = SessionSupervisor.start_session(base)

    metadata = %{
      session_pid: pid,
      pending_suspension: suspension
    }

    session = %{base | jido_orchestrator: agent, metadata: metadata}
    :ok = SessionAgent.update_session(pid, session)
    {pid, session, request_id}
  end

  test "resume against an approval-gate suspension does not return :no_matching_suspension" do
    {pid, session, request_id} = seed_orchestrator_with_gated_call()
    on_exit(fn -> SessionAgent.terminate(pid) end)

    response = %ApprovalResponse{
      request_id: request_id,
      decision: :approved,
      data: %{resource: AshHarness.Test.Ticket, action: :assign},
      responded_at: DateTime.utc_now()
    }

    result = Harness.resume(session, response)

    # The terminal shape may be :ok, :halt, or :error depending on what
    # the LLM stub / downstream gate does — but it must NOT be
    # {:error, :no_matching_suspension, _}, which would indicate the
    # `Resume.resume/4` gatekeeping blocked the dispatch entirely.
    refute match?({:error, :no_matching_suspension, _}, result),
           "expected resume to dispatch the :suspend_resume signal; got: #{inspect(result)}"
  end
end
