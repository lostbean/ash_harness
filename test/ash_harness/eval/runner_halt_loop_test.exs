defmodule AshHarness.Eval.RunnerHaltLoopTest do
  @moduledoc """
  TDD regression: when an `AshHarness.Eval` scenario drives an agent
  that uses `confirm_before` actions, `Eval.Runner.loop/5` must
  properly halt → auto-approve → resume → execute through the
  orchestrator strategy.

  Bug: `Eval.Runner.request_payload_data/1` reads
  `request.metadata[:resource]` and `request.metadata[:action]`, but
  the orchestrator strategy's `ApprovalRequest.metadata` is
  `%{tool_call_id, tool_name}` — `Map.take` returns `%{}`, the
  approval is recorded under `{nil, nil}` in
  `session.metadata.approvals`, and the secondary `ConfirmationGate`
  re-halts on the post-resume dispatch.

  This test exercises the eval runner end-to-end with an LLMStub
  driving a `confirm_before` action via the orchestrator's gated-node
  path. It is expected to fail until `request_payload_data/1` learns
  to reverse-lookup `{resource, action}` from the agent's canonical
  tool list keyed by `metadata.tool_name`.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Eval.Runner
  alias AshHarness.Test.HaltLoopEval
  alias AshHarness.Test.LLMStub

  setup do
    # ReqLLM's Anthropic provider looks up an API key before issuing the
    # request. The stub plug intercepts before any HTTP call, but the
    # key validation runs first — supply a placeholder so we never see
    # `:api_key_missing`.
    Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-test-stub")
    on_exit(fn -> Application.delete_env(:req_llm, :anthropic_api_key) end)
    :ok
  end

  test "auto_confirm :always_approve drives confirm_before through halt → resume → execute" do
    pid =
      LLMStub.start_link!([
        # Turn 1: emit the confirm_before tool call against the
        # scenario-setup-fixed ticket id.
        LLMStub.tool_use("ticket__assign", %{
          "id" => HaltLoopEval.ticket_id(),
          "assigned_to" => "alice",
          "reasoning" => "User asked."
        }),
        # Turn 2 (post-approval): a final answer once the tool ran.
        LLMStub.text("Done.")
      ])

    [scenario] = HaltLoopEval.scenarios()

    result =
      Runner.run(scenario,
        auto_confirm: :always_approve,
        req_options: [plug: {LLMStub, pid}]
      )

    assert result.passed,
           "expected scenario to pass; got: terminated_reason=" <>
             inspect(result.terminated_reason) <>
             ", gates=" <>
             inspect(result.gate_results, pretty: true) <>
             ", trajectory=" <>
             inspect(result.session_trajectory, pretty: true)
  end
end
