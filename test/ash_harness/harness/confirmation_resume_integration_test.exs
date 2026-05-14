defmodule AshHarness.Harness.ConfirmationResumeIntegrationTest do
  @moduledoc """
  Integration test for the real halt → resume → execute path through
  `Harness.run/3` + `Harness.resume/2`.

  This test goes through the orchestrator (`Jido.Composer.Orchestrator`)
  with a fake LLM stub plug that emits a `confirm_before` tool call on
  the first turn and a final text reply on the second turn. The
  contract under test:

    1. `Harness.run/3` returns `{:halt, %ApprovalRequest{}, session}` on
       a `confirm_before` tool call (F1 — orchestrator factory wires
       `approval_gate.gated_node_names` from the agent's confirm_before
       set).
    2. `Harness.resume/2` routes through `do_resume/3` (a `%Suspension{}`
       has been persisted in `session.metadata.pending_suspension`),
       calls `Jido.Composer.Resume.resume/4`, drives the strategy back
       through `__query_sync_loop__/3`, and **actually dispatches the
       approved tool**.
    3. The Ash action runs end-to-end — the ticket's `assigned_to`
       attribute reflects the LLM's tool call input.
    4. The session trajectory records the executed `:assign` with
       `result_status: :ok`.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Eval.Sandbox
  alias AshHarness.Harness
  alias AshHarness.Test.LLMStub
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent
  alias Jido.Composer.HITL.ApprovalRequest
  alias Jido.Composer.HITL.ApprovalResponse

  setup do
    # ReqLLM's Anthropic provider looks up an API key before issuing the
    # request. The stub plug intercepts before any HTTP call, but the
    # key validation runs first — supply a placeholder so we never see
    # `:api_key_missing`.
    Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-test-stub")
    on_exit(fn -> Application.delete_env(:req_llm, :anthropic_api_key) end)

    {:ok, _} = Sandbox.open([Ticket])

    {:ok, ticket} =
      Ash.create(Ticket, %{title: "T-resume", priority: :medium},
        action: :open_ticket,
        authorize?: false
      )

    {:ok, ticket: ticket}
  end

  test "halt-then-resume executes the gated tool and assigns the ticket", %{ticket: ticket} do
    pid =
      LLMStub.start_link!([
        # Turn 1: LLM emits the confirm_before tool call.
        LLMStub.tool_use("ticket__assign", %{
          "id" => ticket.id,
          "assigned_to" => "alice",
          "reasoning" => "Per the triage strategy, alice has the lightest load."
        }),
        # Turn 2 (post-approval): final answer once the tool has executed.
        LLMStub.text("Assigned to alice.")
      ])

    session = Harness.new_session(TriageAgent, req_options: [plug: {LLMStub, pid}])
    on_exit(fn -> Harness.terminate(session) end)

    # --- 1) Halt ---------------------------------------------------
    assert {:halt, request, halted} =
             Harness.run(session, "Please assign ticket #{ticket.id} to alice.")

    assert %ApprovalRequest{} = request,
           "expected an ApprovalRequest on the confirm_before halt, got: #{inspect(request)}"

    assert request.metadata.tool_name == "ticket__assign",
           "expected tool_name to be ticket__assign in request metadata, got: #{inspect(request.metadata)}"

    # The Suspension carrying the request must be persisted on the session
    # so resume/2 can route through do_resume/3 (not the v0.1.0 fallback).
    assert match?(%Jido.Composer.Suspension{}, halted.metadata.pending_suspension),
           "expected pending_suspension on session.metadata after halt, got: " <>
             "#{inspect(Map.get(halted.metadata, :pending_suspension))}"

    # --- 2) Resume with approval -----------------------------------
    response = %ApprovalResponse{
      request_id: request.id,
      decision: :approved,
      data: %{resource: Ticket, action: :assign},
      responded_at: DateTime.utc_now()
    }

    assert {:ok, reply, final_session} = Harness.resume(halted, response)

    # The reply is the final-answer text from the stub's second response.
    assert is_binary(extract_text(reply)),
           "expected text reply from stub, got: #{inspect(reply)}"

    # --- 3) The action actually ran --------------------------------
    {:ok, fresh} = Ash.get(Ticket, ticket.id, authorize?: false)

    assert fresh.assigned_to == "alice",
           "expected ticket.assigned_to to be \"alice\" after approved resume; " <>
             "trajectory was: " <>
             inspect(Harness.trajectory(final_session), limit: :infinity, pretty: true)

    # --- 4) Trajectory records the executed :assign ---------------
    trajectory = Harness.trajectory(final_session)

    assert Enum.any?(trajectory, fn entry ->
             entry.result_status == :ok and
               Map.get(entry.intent, :action) == :assign and
               Map.get(entry.intent, :resource) == Ticket
           end),
           "expected trajectory to contain a successful :assign on Ticket; got: " <>
             inspect(trajectory, limit: :infinity, pretty: true)
  end

  test "rejected resume records :confirmation_rejected in trajectory and does NOT mutate", %{
    ticket: ticket
  } do
    pid =
      LLMStub.start_link!([
        # Turn 1: agent emits a confirm_before tool call
        LLMStub.tool_use("ticket__assign", %{
          "id" => ticket.id,
          "assigned_to" => "bob",
          "reasoning" => "Policy says so"
        }),
        # Turn 2 (after rejection): a follow-up answer acknowledging the rejection
        LLMStub.text("OK, will not assign.")
      ])

    session = Harness.new_session(TriageAgent, req_options: [plug: {LLMStub, pid}])

    assert {:halt, %ApprovalRequest{} = request, session} =
             Harness.run(session, "Please assign ticket #{ticket.id} to bob.")

    response = %ApprovalResponse{
      request_id: request.id,
      decision: :rejected,
      data: %{resource: Ticket, action: :assign},
      responded_at: DateTime.utc_now()
    }

    assert {:ok, _reply, final_session} = Harness.resume(session, response)

    # After rejection, the orchestrator strategy should have written a
    # tool-result describing the rejection and re-entered the LLM loop,
    # consuming the second stub response. The queue should be empty.
    assert LLMStub.pending(pid) == [],
           "expected LLM stub queue to be drained after rejection resume; " <>
             "pending: #{inspect(LLMStub.pending(pid))}"

    # The ticket must NOT have been mutated.
    {:ok, fresh} = Ash.get(Ticket, ticket.id, authorize?: false)
    refute fresh.assigned_to == "bob"

    # The trajectory must contain a :confirmation_rejected entry for :assign.
    trajectory = Harness.trajectory(final_session)

    assert Enum.any?(trajectory, fn entry ->
             entry.result_status == :confirmation_rejected and
               entry.intent.resource == Ticket and
               entry.intent.action == :assign
           end),
           "expected a :confirmation_rejected trajectory entry; got: #{inspect(trajectory)}"

    Harness.terminate(final_session)
  end

  test "Repair.format_feedback/2 has a :confirmation_rejected clause that describes the rejection" do
    intent = %AshHarness.Harness.Intent{
      resource: Ticket,
      action: :assign,
      input: %{},
      request_id: "r"
    }

    text = AshHarness.Harness.Repair.format_feedback(:confirmation_rejected, intent)
    assert is_binary(text)
    assert text =~ "rejected" or text =~ "Rejected"
    # Must be the dedicated clause, not the generic atom fallback.
    refute text == "Action failed: confirmation_rejected."
  end

  # --- helpers -----------------------------------------------------

  defp extract_text(%{text: t}) when is_binary(t), do: t
  defp extract_text(%{"text" => t}) when is_binary(t), do: t
  defp extract_text(text) when is_binary(text), do: text
  defp extract_text(other), do: inspect(other)
end
