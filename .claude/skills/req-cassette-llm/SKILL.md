---
name: req-cassette-llm
description: Set up `req_cassette` correctly for LLM agent tests so replay-mode actually matches recorded interactions. Use when configuring or debugging `ReqCassette.with_cassette/3` against Anthropic/OpenAI/Jido orchestrators — multi-turn agent flows produce non-deterministic IDs (`msg_*`, `toolu_*`, `chatcmpl-*`, `call_*`, UUIDs) that exact-byte matching cannot survive without templates.
metadata:
  author: ash_harness
  version: "1.0"
---

# Making `req_cassette` work for LLM agent tests

**The trap.** A multi-turn LLM cassette records turn 1's request/response, then turn 2's request — which embeds turn 1's `toolu_*` ID as a `tool_use_id` in the next request body. Every fresh LLM call generates a different `toolu_*`. On replay, turn 2's request body bytes differ from the recording, ReqCassette can't match, and the test fails.

The same trap hits anything where the LLM's own output round-trips into a later request: `msg_*` IDs, OpenAI `chatcmpl-*`/`call_*` IDs, fresh UUIDs from `Ash.UUID.generate`, RFC3339 timestamps, etc.

`req_cassette` ships a templating system that auto-extracts these into placeholders during recording and rebinds them during replay. The single-turn cassette will replay clean without it; the multi-turn one won't.

## Minimum viable config

For any test that drives an LLM through more than one turn:

```elixir
ReqCassette.with_cassette(name,
  cassette_dir: "test/cassettes",
  mode: mode,
  template: [preset: :llm],
  filter_request_headers: ["authorization", "x-api-key", "cookie"],
  filter_request: &MyModule.normalize_tool_schemas/1
) do
  # ...
end
```

What each piece earns:

| Option | Why |
|---|---|
| `template: [preset: :llm]` | Auto-handles `msg_*`, `toolu_*`, `req_*` (Anthropic) + `chatcmpl-*`, `call_*` (OpenAI). Without this, multi-turn replays will always fail body matching. |
| `filter_request_headers` | Scrubs the API key before write so cassettes are commit-safe. |
| `filter_request` | Applied symmetrically during record AND replay match. Use it to sort non-deterministic JSON ordering (Ash/Jido tool schemas emit `"required": [...]` in arbitrary order). |

Available presets: `:anthropic`, `:openai`, `:llm` (both), `:common` (UUIDs + ISO timestamps). Combine with custom patterns:

```elixir
template: [preset: :llm, patterns: [order_id: ~r/ORD-\d+/]]
```

## When `:llm` preset isn't enough

If request bodies contain non-deterministic content beyond IDs (e.g. chain-of-thought text from the LLM that gets echoed into a later turn's prompt), narrow the matcher:

```elixir
match_requests_on: [:method, :uri]  # default is [:method, :uri, :query, :headers, :body]
```

This trades replay-strictness for replay-stability. Multi-turn agent tests almost always want this. Add `:body` back only on tests where the body bytes are genuinely deterministic.

## Cross-process / GenServer agents

If the agent runs in a separate process (GenServer, Oban worker, Jido orchestrator with internal `Task.async`), pass `shared: true` so spawned processes pick up the same session:

```elixir
ReqCassette.with_cassette(name, [shared: true, ...], fn plug -> ... end)
```

Without this, interactions spawned from child processes get lost.

## Recording flow

Gate it behind one env var:

```elixir
mode = if System.get_env("RECORD_CASSETTES"), do: :record, else: :replay
```

Workflow:

```bash
RECORD_CASSETTES=1 ANTHROPIC_API_KEY=sk-... mix test path/to/test.exs    # record
mix test                                                                  # replay (default)
```

In `config/test.exs`, set the provider API key to a placeholder so ReqLLM's pre-flight validation passes in replay mode:

```elixir
config :req_llm, :anthropic_api_key, "sk-ant-test-placeholder"
```

In record mode, leave the real key on the env; the test task should NOT override it:

```elixir
case System.get_env("RECORD_CASSETTES") do
  nil -> Application.put_env(:req_llm, :anthropic_api_key, "sk-ant-test-placeholder")
  _ -> :ok
end
```

## The `filter_request` normalizer

Critical detail: `:filter_request` is applied during both recording and matching — anything you normalize gets normalized symmetrically. Use it to flatten non-deterministic structure (NOT to hide bytes you don't want recorded; use `filter_request_headers` / `filter_sensitive_data` for that).

Typical normalizer for Ash/Jido tool schemas (the `"required": [...]` array comes out unordered):

```elixir
def cassette_normalize_request(request) do
  update_in(request, ["body_json"], &normalize_required_fields/1)
end

defp normalize_required_fields(%{"required" => required} = node) when is_list(required) do
  node
  |> Map.put("required", Enum.sort(required))
  |> Enum.into(%{}, fn {k, v} -> {k, normalize_required_fields(v)} end)
end

defp normalize_required_fields(%{} = node),
  do: Enum.into(node, %{}, fn {k, v} -> {k, normalize_required_fields(v)} end)

defp normalize_required_fields(list) when is_list(list),
  do: Enum.map(list, &normalize_required_fields/1)

defp normalize_required_fields(other), do: other
```

Pass it as `&MyModule.cassette_normalize_request/1`, not an anonymous fn — ReqCassette serializes options for cache-key purposes, and anonymous fns can confuse equality checks.

## Debugging a mismatch

`ReqCassette` truncates its mismatch errors through Logger. To see the actual diff, dump live requests to disk via a temporary `filter_request`:

```elixir
filter_request: fn req ->
  if dir = System.get_env("CASSETTE_DEBUG_DIR") do
    File.mkdir_p!(dir)
    slot = :persistent_term.get({:slot, name}, 0)
    :persistent_term.put({:slot, name}, slot + 1)
    File.write!(Path.join(dir, "#{name}-#{slot}.json"), Jason.encode!(req, pretty: true))
  end
  req
end
```

Then `jq` against the recorded cassette's `interactions[N].request.body_json` and diff. Look for:

1. **System prompt drift** — has the agent's rendered context grown a new section since recording?
2. **Tool schema reordering** — is `"required": [...]` in a different order?
3. **Non-ID dynamic content** — is there a UUID or timestamp the `:llm` preset doesn't cover? Add it to `template.patterns`.

For step 3, `DEBUG_CASSETTE=1` flips on `template: [preset: :llm, debug: true]` which logs every template binding decision.

## Path gotchas

`cassette_dir:` is resolved relative to `File.cwd!()` at cassette-write time. If your test task runs from a parent project but writes from a path-dep child, the cwd is the *parent's*, not the child's — recordings land somewhere unexpected. Either:

- Use an absolute path: `cassette_dir: Path.expand("test/cassettes", __DIR__)`, or
- `cd` into the child project before running the test task.

## What NOT to do

- **Don't try to make recordings byte-stable manually.** Patching out IDs in the recorded JSON works for a single matching strategy but the next dynamic field will burn you. Use templates.
- **Don't use anonymous fns in cassette opts.** ReqCassette includes opts in its cache key; closures over per-test state break equality. Module-bound public functions are stable.
- **Don't put `match_requests_on: [:method, :uri]` everywhere by default.** It hides real regressions in single-turn deterministic tests. Reserve it for multi-turn agent flows where body-byte stability is genuinely impossible.
- **Don't share cassettes across `mode: :record` runs that hit different model versions.** Provider responses change between snapshots; mixing recordings from two model IDs produces a cassette that replays inconsistently.

## When you're configuring this in ash_harness

`lib/ash_harness/eval/runner.ex` is the canonical wiring point. `Eval.Runner.cassette_normalize_request/1` is the project's `:filter_request` callback. Template preset `:llm` is on by default. Don't replicate the opts at every callsite — extend the runner.

## Reference

- `:template` API: `deps/req_cassette/lib/req_cassette/template/presets.ex` (preset patterns)
- Filter pipeline: `deps/req_cassette/lib/req_cassette/plug.ex` `build_and_filter_incoming_request/3`
- Working example with all of the above: `/code/edgar/astrobee/test/support/cassette_case.ex`
