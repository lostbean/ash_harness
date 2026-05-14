defmodule AshHarness.ToolGenTest do
  use ExUnit.Case, async: true

  alias AshHarness.Test.TriageAgent

  describe "generated Jido.Action modules" do
    test "one module per scoped action" do
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Tools.Ticket.Read)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Tools.Ticket.OpenTicket)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Tools.Ticket.Assign)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Tools.Project.Read)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Tools.Member.Read)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Tools.Member.ByWorkload)
    end

    test "generated module identifies its (resource, action)" do
      mod = AshHarness.Test.TriageAgent.Tools.Ticket.Assign
      assert mod.__resource__() == AshHarness.Test.Ticket
      assert mod.__action_name__() == :assign
      assert mod.__agent__() == TriageAgent
    end

    test "generated module's run/2 delegates to harness dispatcher" do
      mod = AshHarness.Test.TriageAgent.Tools.Ticket.Read
      # With an empty ETS table and no params, a :read returns an empty list.
      assert {:ok, %{count: 0, records: []}} = mod.run(%{}, %{})
    end

    test "generated module exposes its canonical struct" do
      mod = AshHarness.Test.TriageAgent.Tools.Ticket.Assign
      canonical = mod.__canonical__()
      assert canonical.tool_name == "ticket__assign"
      assert canonical.action_name == :assign
    end
  end

  describe "generated Skill modules" do
    test "one Skill module per scoped resource" do
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Skills.Ticket)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Skills.Project)
      assert Code.ensure_loaded?(AshHarness.Test.TriageAgent.Skills.Member)
    end

    test "Skill module emits a %Jido.Composer.Skill{}" do
      skill = AshHarness.Test.TriageAgent.Skills.Ticket.skill()
      assert %Jido.Composer.Skill{} = skill
      assert skill.name == "ticket"
      assert is_list(skill.tools)
      assert AshHarness.Test.TriageAgent.Tools.Ticket.Read in skill.tools
    end

    test "Skill's prompt_fragment is the rendered resource detail" do
      skill = AshHarness.Test.TriageAgent.Skills.Ticket.skill()
      assert skill.prompt_fragment =~ "## Attributes"
    end
  end

  describe "AshHarness.Tool.dynamic/2" do
    test "builds a tool struct" do
      tool =
        AshHarness.Tool.dynamic(
          name: "custom_assign",
          description: "Custom assign tool.",
          resource: AshHarness.Test.Ticket,
          action: :assign
        )

      assert tool.name == "custom_assign"
      assert tool.resource == AshHarness.Test.Ticket
      assert tool.canonical != nil
      assert tool.schema != []
    end

    test "input_builder is preserved on the dynamic tool" do
      builder = fn input -> Map.put(input, :_marker, true) end

      tool =
        AshHarness.Tool.dynamic(
          name: "n",
          description: "d",
          input_builder: builder
        )

      assert tool.input_builder == builder
    end
  end
end
