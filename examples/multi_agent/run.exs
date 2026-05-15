# A runnable demo of the AshHarness delegation surface. Reuses the
# `AshHarness.Test.DelegatingAgent` from the test support tree, which
# declares `delegates_to AshHarness.Test.TriageAgent`. Run from the
# repository root:
#
#     mix run examples/multi_agent/run.exs
#
# Demonstrates:
#   1. Caller introspection (`Info.delegates/1`, `delegate_for?/2`).
#   2. Delegate isolation: the caller's actor is NOT propagated; the
#      delegate's reachability graph is its own.
#   3. The `delegate` meta-tool that ToolGen emits when `delegates_to`
#      is non-empty.

caller = AshHarness.Test.DelegatingAgent
target = AshHarness.Test.TriageAgent

IO.puts("Caller:  #{AshHarness.Agent.Info.name(caller)}")
IO.puts("Target:  #{AshHarness.Agent.Info.name(target)}")

IO.puts("\nCaller's declared delegates:")

for d <- AshHarness.Agent.Info.delegates(caller) do
  IO.puts("  - #{inspect(d.agent_module)}: #{d.for}")
end

IO.puts("\nIsolation: each agent uses its own actor and scope.")
IO.puts("  caller actor:  #{inspect(AshHarness.Agent.Info.actor(caller))}")
IO.puts("  target actor:  #{inspect(AshHarness.Agent.Info.actor(target))}")

caller_scope = AshHarness.Agent.Info.scoped_resources(caller)
target_scope = AshHarness.Agent.Info.scoped_resources(target)
IO.puts("  caller scope:  #{inspect(caller_scope)}")
IO.puts("  target scope:  #{inspect(target_scope)}")

caller_only = caller_scope -- target_scope
target_only = target_scope -- caller_scope
IO.puts("  resources only the caller sees: #{inspect(caller_only)}")
IO.puts("  resources only the target sees: #{inspect(target_only)}")

IO.puts("\nDelegate meta-tool emitted by ToolGen:")

delegate_tool =
  Enum.find(AshHarness.Agent.Info.tool_list(caller), fn t ->
    t.tool_name == "delegate"
  end)

case delegate_tool do
  nil ->
    if AshHarness.Agent.Info.delegates(caller) == [] do
      IO.puts("  (none — `delegates_to` is empty on this agent)")
    else
      IO.puts("  (delegate meta-tool emission via ToolGen is not yet wired —")
      IO.puts("   see task 22.3 in openspec/changes/bootstrap-ash-harness-v0-1-0)")
      IO.puts("   Use `AshHarness.Delegation.initiate/4` directly for now:")
      IO.puts("     {:ok, reply, caller_session, target_traj} =")
      IO.puts("       AshHarness.Delegation.initiate(caller_session, target, question, opts)")
    end

  %{tool_name: name, description: desc} ->
    IO.puts("  #{name} :: #{desc}")
end

IO.puts(
  "\nDelegation cap (depth): #{Application.get_env(:ash_harness, :delegation_max_depth, 3)}"
)

IO.puts("See `AshHarness.Delegation` and ADR 0004 for the rationale.")
