# A minimal Mix.install-free demo of the AshHarness agent introspection
# surface. Run from the repository root:
#
#     mix run examples/triage/run.exs

agent = AshHarness.Test.TriageAgent

IO.puts("Agent: #{AshHarness.Agent.Info.name(agent)}")
IO.puts("Description: #{AshHarness.Agent.Info.description(agent)}")
IO.puts("\nScoped resources:")

for r <- AshHarness.Agent.Info.scoped_resources(agent) do
  IO.puts("  - #{inspect(r)}: #{inspect(AshHarness.Agent.Info.scoped_actions(agent, r))}")
end

IO.puts("\nTool list (#{length(AshHarness.Agent.Info.tool_list(agent))} tools):")

for tool <- AshHarness.Agent.Info.tool_list(agent) do
  IO.puts("  - #{tool.tool_name} :: #{inspect(tool.action_type)}")
end

ctx = AshHarness.ContextRenderer.render(agent, cache?: false)
IO.puts("\nRendered initial context (#{ctx.token_estimate} estimated tokens):\n")
IO.puts(ctx.initial_text)
