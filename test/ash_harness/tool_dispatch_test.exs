defmodule AshHarness.ToolDispatchTest do
  use ExUnit.Case, async: false

  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent
  alias AshHarness.Tool

  setup do
    AshHarness.Eval.Sandbox.open([Ticket])

    {:ok, pid} =
      SessionSupervisor.start_session(%Session{
        agent: TriageAgent,
        actor: %{id: "u"},
        request_id: "req-tool-dispatch",
        metadata: %{}
      })

    on_exit(fn -> SessionAgent.terminate(pid) end)

    session = %Session{
      agent: TriageAgent,
      actor: %{id: "u"},
      request_id: "req-tool-dispatch",
      metadata: %{session_pid: pid}
    }

    ctx = %{
      ash_harness_session_pid: pid,
      ash_harness_session: session,
      request_id: "req-tool-dispatch"
    }

    {:ok, pid: pid, ctx: ctx}
  end

  describe "Tool.run/3 / Tool.invoke/3" do
    test "dispatches through gate pipeline like a compile-time tool", %{ctx: ctx} do
      tool =
        Tool.dynamic(
          name: "ticket__read",
          description: "Read tickets",
          resource: Ticket,
          action: :read
        )

      assert {:ok, %{count: _, records: _}} = Tool.run(tool, %{}, ctx)
    end

    test "scope violation refuses dynamic tool too", %{ctx: ctx} do
      tool =
        Tool.dynamic(
          name: "ticket__destroy",
          description: "Destroy (out of scope)",
          resource: Ticket,
          action: :destroy
        )

      assert {:error, msg} = Tool.run(tool, %{id: "x"}, ctx)
      assert msg =~ "not in scope"
    end

    test "input_builder transforms input before dispatch", %{ctx: ctx} do
      tool =
        Tool.dynamic(
          name: "ticket__open_with_default_priority",
          description: "Open with high priority",
          resource: Ticket,
          action: :open_ticket,
          input_builder: fn input -> Map.put(input, :priority, :high) end
        )

      {:ok, %{record: rec}} = Tool.run(tool, %{title: "Dyn"}, ctx)
      assert rec[:priority] == :high or rec.priority == :high
    end
  end

  describe "compile-time / dynamic parity" do
    test "same inputs produce structurally equal results", %{ctx: ctx} do
      tool =
        Tool.dynamic(
          name: "ticket__open_ticket",
          description: "Open",
          resource: Ticket,
          action: :open_ticket
        )

      # Compile-time path
      compile_mod =
        AshHarness.ToolGen.action_module(
          TriageAgent,
          AshHarness.Schema.canonical_for(Ticket, :open_ticket)
        )

      compile_result = compile_mod.run(%{title: "Same"}, ctx)
      dynamic_result = Tool.run(tool, %{title: "Same"}, ctx)

      # Both should be {:ok, %{record: ...}}
      assert match?({:ok, %{record: _}}, compile_result)
      assert match?({:ok, %{record: _}}, dynamic_result)

      # Result structures match
      {:ok, %{record: cr}} = compile_result
      {:ok, %{record: dr}} = dynamic_result
      assert Map.keys(cr) |> Enum.sort() == Map.keys(dr) |> Enum.sort()
    end
  end
end
