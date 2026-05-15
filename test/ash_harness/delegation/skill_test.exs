defmodule AshHarness.Delegation.SkillTest do
  use ExUnit.Case, async: false

  alias AshHarness.Delegation.Skill
  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.RenderedContext
  alias AshHarness.Test.DelegatingAgent
  alias AshHarness.Test.ReadOnlyAgent
  alias AshHarness.Test.TriageAgent
  alias AshHarness.ToolGen.OrchestratorModule

  defp parent_session_with_pid(agent_module) do
    rendered = %RenderedContext{
      initial_text: "ctx",
      token_estimate: 0,
      resource_details: %{},
      warnings: []
    }

    session = %Session{
      agent: agent_module,
      actor: %{id: "u"},
      request_id: "req-parent",
      rendered_context: rendered
    }

    {:ok, pid} = SessionSupervisor.start_session(session)
    {session, pid}
  end

  describe "orchestrator wiring" do
    test "DelegatingAgent's orchestrator contains AshHarness.Delegation.Skill" do
      mod = OrchestratorModule.orchestrator_module(DelegatingAgent)
      nodes = mod.tool_nodes()

      assert Skill in Enum.map(nodes, fn
               {m, _} -> m
               m -> m
             end)
    end

    test "AshHarness.Delegation.Skill is NOT gated by requires_approval" do
      mod = OrchestratorModule.orchestrator_module(DelegatingAgent)
      nodes = mod.tool_nodes()

      refute Enum.any?(nodes, fn
               {Skill, opts} -> Keyword.get(opts, :requires_approval, false)
               _ -> false
             end)
    end

    test "ReadOnlyAgent (no delegates_to) does NOT include the skill node" do
      mod = OrchestratorModule.orchestrator_module(ReadOnlyAgent)
      nodes = mod.tool_nodes()

      refute Skill in Enum.map(nodes, fn
               {m, _} -> m
               m -> m
             end)
    end

    test "TriageAgent (no delegates_to) does NOT include the skill node" do
      mod = OrchestratorModule.orchestrator_module(TriageAgent)
      nodes = mod.tool_nodes()

      refute Skill in Enum.map(nodes, fn
               {m, _} -> m
               m -> m
             end)
    end
  end

  describe "skill.run/2 alias resolution" do
    test "returns an error when the parent session has no session pid in ctx" do
      params = %{target: "anything", question: "?"}
      assert {:error, msg} = Skill.run(params, %{})
      assert is_binary(msg)
    end

    test "returns an error when the target alias is unknown" do
      {_session, pid} = parent_session_with_pid(DelegatingAgent)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      ambient_key = Jido.Composer.Context.ambient_key()

      params = %{
        :target => "nonexistent",
        :question => "tell me something",
        ambient_key => %{
          ash_harness_session_pid: pid,
          request_id: "req-parent"
        }
      }

      assert {:error, msg} = Skill.run(params, %{})
      assert msg =~ "Unknown delegate target"
      assert msg =~ "nonexistent"
      # Should list the declared aliases — DelegatingAgent has `as: "triage"`
      assert msg =~ "triage"
    end

    test "missing target or question yields an error" do
      {_session, pid} = parent_session_with_pid(DelegatingAgent)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      ambient_key = Jido.Composer.Context.ambient_key()

      ambient = %{
        ash_harness_session_pid: pid,
        request_id: "req-parent"
      }

      assert {:error, _} =
               Skill.run(
                 %{ambient_key => ambient, :target => "", :question => "?"},
                 %{}
               )

      assert {:error, _} =
               Skill.run(
                 %{ambient_key => ambient, :target => "triage", :question => ""},
                 %{}
               )
    end
  end

  describe "skill.run/2 — case-insensitive alias match" do
    test "resolves alias case-insensitively and reaches Delegation.initiate/4" do
      {_session, pid} = parent_session_with_pid(DelegatingAgent)
      on_exit(fn -> SessionAgent.terminate(pid) end)

      ambient_key = Jido.Composer.Context.ambient_key()

      params = %{
        :target => "TRIAGE",
        :question => "?",
        ambient_key => %{
          ash_harness_session_pid: pid,
          request_id: "req-parent"
        }
      }

      # We don't have an LLM hooked up; the child session will fail at
      # the orchestrator level. We only need to confirm we got past the
      # alias-resolution stage and reached initiate (i.e. NOT an
      # "Unknown delegate target" error). Any other error is fine — it
      # means we matched the alias and dispatched.
      result = Skill.run(params, %{})

      case result do
        {:error, msg} when is_binary(msg) ->
          refute msg =~ "Unknown delegate target",
                 "expected case-insensitive alias match; got: #{msg}"

        _ ->
          :ok
      end
    end
  end

  describe "trajectory data on a successful delegation" do
    @describetag :integration_llm_stub

    setup do
      Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-test-stub")
      on_exit(fn -> Application.delete_env(:req_llm, :anthropic_api_key) end)
      :ok
    end

    test "skill returns the child's text reply and appends a delegation trajectory entry" do
      # Child (TriageAgent) immediately answers with text. The stub
      # response queue contains one `text` message that becomes the
      # final `end_turn` reply.
      child_stub =
        AshHarness.Test.LLMStub.start_link!([
          AshHarness.Test.LLMStub.text("All good — no action needed.")
        ])

      # Open the parent session WITH `req_options` so OrchestratorFactory
      # picks them up. The skill will forward them to the child via
      # session.options.
      parent_session =
        Harness.new_session(DelegatingAgent,
          req_options: [plug: {AshHarness.Test.LLMStub, child_stub}]
        )

      on_exit(fn -> Harness.terminate(parent_session) end)

      pid = parent_session.metadata.session_pid
      ambient_key = Jido.Composer.Context.ambient_key()

      params = %{
        :target => "triage",
        :question => "anything?",
        ambient_key => %{
          ash_harness_session_pid: pid,
          request_id: "req-parent-1"
        }
      }

      assert {:ok, %{reply: reply}} = Skill.run(params, %{})
      assert reply == "All good — no action needed."

      # Caller's trajectory has one entry with data.reply_text and
      # data.target_trajectory_id.
      traj = Harness.trajectory(parent_session)

      delegation_entry =
        Enum.find(traj, fn e ->
          match?(%{intent: %{type: :delegation}}, e) or
            (is_map(e.intent) and e.intent[:type] == :delegation)
        end)

      assert delegation_entry,
             "expected a delegation entry in parent's trajectory, got: #{inspect(traj)}"

      assert delegation_entry.data.reply_text == "All good — no action needed."
      assert is_binary(delegation_entry.data.target_trajectory_id)
      assert byte_size(delegation_entry.data.target_trajectory_id) > 0
    end
  end

  describe "child halt — nested HITL deferral" do
    @describetag :integration_llm_stub

    setup do
      Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-test-stub")
      on_exit(fn -> Application.delete_env(:req_llm, :anthropic_api_key) end)

      {:ok, _} = AshHarness.Eval.Sandbox.open([AshHarness.Test.Ticket])

      {:ok, ticket} =
        Ash.create(AshHarness.Test.Ticket, %{title: "T-skill", priority: :medium},
          action: :open_ticket,
          authorize?: false
        )

      {:ok, ticket: ticket}
    end

    test "returns {:error, text} when the child halts on a confirmation gate", %{ticket: ticket} do
      # Child (TriageAgent) tries to call `ticket__assign`, which is
      # `confirm_before`. The orchestrator will halt with an
      # ApprovalRequest. The skill must convert that to a text error per
      # the nested-HITL deferral (design.md open question).
      child_stub =
        AshHarness.Test.LLMStub.start_link!([
          AshHarness.Test.LLMStub.tool_use("ticket__assign", %{
            "id" => ticket.id,
            "assigned_to" => "alice",
            "reasoning" => "needed"
          })
        ])

      parent_session =
        Harness.new_session(DelegatingAgent,
          req_options: [plug: {AshHarness.Test.LLMStub, child_stub}]
        )

      on_exit(fn -> Harness.terminate(parent_session) end)

      pid = parent_session.metadata.session_pid
      ambient_key = Jido.Composer.Context.ambient_key()

      params = %{
        :target => "triage",
        :question => "assign the ticket",
        ambient_key => %{
          ash_harness_session_pid: pid,
          request_id: "req-parent-halt"
        }
      }

      assert {:error, msg} = Skill.run(params, %{})
      assert msg =~ "delegate halted"
      assert msg =~ "requires confirmation"
    end
  end
end
