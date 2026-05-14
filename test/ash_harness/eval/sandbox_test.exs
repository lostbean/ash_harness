defmodule AshHarness.Eval.SandboxTest do
  use ExUnit.Case, async: false

  alias AshHarness.Eval.Sandbox
  alias AshHarness.Test.Project

  test "opening the sandbox clears state between scenarios" do
    # Scenario A: create a record.
    {:ok, handle_a} = Sandbox.open([Project])
    {:ok, _p1} = Ash.create(Project, %{name: "scenario-a"})
    {:ok, [%Project{name: "scenario-a"}]} = Ash.read(Project)
    :ok = Sandbox.close(handle_a)

    # Scenario B: the prior record should be gone before any setup runs.
    {:ok, handle_b} = Sandbox.open([Project])
    assert {:ok, []} = Ash.read(Project)

    {:ok, _p2} = Ash.create(Project, %{name: "scenario-b"})
    assert {:ok, [%Project{name: "scenario-b"}]} = Ash.read(Project)
    :ok = Sandbox.close(handle_b)
  end

  test "reset_resource/1 is idempotent on already-empty resources" do
    assert :ok = Sandbox.reset_resource(Project)
    assert :ok = Sandbox.reset_resource(Project)
  end
end
