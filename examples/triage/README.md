# Triage Example

The smallest possible AshHarness setup. One Ash domain with one resource
(`Ticket`); one agent (`TriageAgent`) scoped over reads and a single
write action.

This example is **not** a runnable application — it lives here as
documentation. The runtime needs a real LLM (or a `jido_composer`
LLMStub) to actually issue tool calls.

The agent's tool surface is generated at compile time. You can inspect
it without an LLM:

```elixir
iex> AshHarness.Agent.Info.tool_list(MyApp.TriageAgent)
[%AshHarness.Schema.Canonical{tool_name: "ticket__read", ...}, ...]
```
