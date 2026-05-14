defmodule AshHarness.Harness.TokensUsedTest do
  @moduledoc """
  Tests for `AshHarness.Harness.tokens_used/1` — extracts cumulative
  token usage from the session's underlying Jido orchestrator agent.

  Two scenarios:

    1. **Unit** — a fresh session has no LLM activity yet, so
       `tokens_used/1` returns 0.
    2. **Synthetic-state unit** — a hand-built session with a seeded
       `_obs.cumulative_tokens.total` returns that total verbatim.
    3. **Integration** — drive the orchestrator with `LLMStub`, which
       embeds `usage: %{input_tokens: 100, output_tokens: 50}` in every
       response. After a halt → approve → final-answer cycle, the
       cumulative total on the session must be strictly positive.
  """

  use ExUnit.Case, async: false

  alias AshHarness.Eval.Sandbox
  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Test.LLMStub
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent
  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.Composer.HITL.ApprovalRequest
  alias Jido.Composer.HITL.ApprovalResponse
  alias Jido.Composer.Orchestrator.Obs

  test "tokens_used/1 returns 0 for a fresh session" do
    session = Harness.new_session(TriageAgent)
    on_exit(fn -> Harness.terminate(session) end)

    assert Harness.tokens_used(session) == 0
  end

  test "tokens_used/1 returns 0 when the session has no orchestrator" do
    assert Harness.tokens_used(%Session{jido_orchestrator: nil}) == 0
  end

  test "tokens_used/1 reads cumulative_tokens.total from the orchestrator's strat state" do
    base_agent = %Agent{state: %{}}

    seeded_agent =
      StratState.put(base_agent, %{
        _obs: %Obs{cumulative_tokens: %{prompt: 700, completion: 250, total: 950}}
      })

    session = %Session{jido_orchestrator: seeded_agent}

    assert Harness.tokens_used(session) == 950
  end

  describe "integration with LLMStub" do
    setup do
      Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-test-stub")
      on_exit(fn -> Application.delete_env(:req_llm, :anthropic_api_key) end)

      {:ok, _} = Sandbox.open([Ticket])

      {:ok, ticket} =
        Ash.create(Ticket, %{title: "T-tokens", priority: :medium},
          action: :open_ticket,
          authorize?: false
        )

      {:ok, ticket: ticket}
    end

    test "tokens_used/1 accumulates from the stub's usage across a halt-resume cycle", %{
      ticket: ticket
    } do
      pid =
        LLMStub.start_link!([
          LLMStub.tool_use("ticket__assign", %{
            "id" => ticket.id,
            "assigned_to" => "alice",
            "reasoning" => "ok"
          }),
          LLMStub.text("Done.")
        ])

      session = Harness.new_session(TriageAgent, req_options: [plug: {LLMStub, pid}])
      on_exit(fn -> Harness.terminate(session) end)

      assert {:halt, %ApprovalRequest{} = request, halted} =
               Harness.run(session, "Please assign ticket #{ticket.id} to alice.")

      # After the first LLM call, the cumulative total must be > 0.
      assert Harness.tokens_used(halted) > 0,
             "expected tokens_used to be > 0 after one LLM call; got: " <>
               "#{Harness.tokens_used(halted)}"

      response = %ApprovalResponse{
        request_id: request.id,
        decision: :approved,
        data: %{resource: Ticket, action: :assign},
        responded_at: DateTime.utc_now()
      }

      assert {:ok, _reply, final} = Harness.resume(halted, response)

      # Two LLM round-trips each report 150 tokens (100 + 50), so
      # cumulative is exactly 300.
      total = Harness.tokens_used(final)

      assert total >= 300,
             "expected tokens_used ≥ 300 across two LLM calls; got: #{total}"
    end
  end
end
