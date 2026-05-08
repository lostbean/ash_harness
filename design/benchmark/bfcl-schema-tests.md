# BFCL-style schema unit tests

A lightweight pre-step before the headline τ-bench port: validate
that AshHarness's tool-schema generation produces well-formed schemas
that LLMs can call cleanly.

## Why this matters

Tool-call success rates are dominated by schema quality. Per research:
narrow verb-named tools win, enum descriptions matter, JSON Schema
`required` arrays must be correct, parameter naming should be
consistent. Many agent failures trace to schema bugs that have nothing
to do with the loop or the prompt.

The Berkeley Function Calling Leaderboard (BFCL) tests pure
function-call accuracy: simple, multiple, parallel, multi-turn. The
spirit (not the exact suite) is useful as an internal regression test.

## What we test

Per scoped action in our test resources:

1. **Schema validity**: the rendered Anthropic / OpenAI / MCP schema is
   syntactically valid JSON Schema.
2. **Round-trip**: a sample input that conforms to the schema can be
   parsed back into an `ActionIntent` and routed to the right action.
3. **Required-field detection**: required attributes/arguments appear
   in `required: [...]`.
4. **Enum mapping**: Ash `:atom` types with `one_of` constraints
   produce JSON-Schema enums; descriptions list values.
5. **Type coverage**: every supported Ash type has a renderer test.
6. **Single-call accuracy** (model in the loop): given a synthetic
   prompt, an LLM produces a tool call that conforms to the schema and
   resolves to the intended action.
7. **Parallel-call accuracy**: when given a prompt that warrants two
   independent calls, the LLM emits both correctly.
8. **Schema description quality**: the tool description includes the
   action hint; the description fits within reasonable length bounds
   (≤200 chars).

## Layout

```text
test/ash_harness/schema/
├── canonical_test.exs              # canonical struct derivation
├── ash_type_mapper_test.exs        # type table coverage
├── render/
│   ├── anthropic_test.exs
│   ├── openai_test.exs
│   └── mcp_test.exs
├── round_trip_test.exs             # rendered → parsed → intent
└── llm_call_test.exs               # actual LLM in the loop (Mox stub or real, gated)
```

## Type coverage table

The `ash_type_mapper_test.exs` enforces that *every* Ash type the test
suite resources use has an explicit test. CI fails if a new Ash type
appears in test resources without a matching mapper test.

| Ash type | Test fixture |
| --- | --- |
| `:string` | `Ticket.title` |
| `:atom` (with `one_of`) | `Ticket.status`, `Ticket.priority` |
| `:uuid` | `Ticket.id` |
| `:integer` | `Member.workload_score` |
| `:utc_datetime_usec` | `Ticket.inserted_at` |
| `{:array, :string}` | `Ticket.tags` (added for coverage) |
| `:map` | `Comment.metadata` (added for coverage) |
| `:decimal` | `Order.amount` (added for coverage) |
| `:boolean` | `Member.active` |

## LLM-in-the-loop tests

These run against Jido's `LLMStub` by default (deterministic). A
separate test file gated by `MIX_ENV=integration` runs them against a
real model (Anthropic Claude Sonnet) for occasional verification.

Sample test:

```elixir
test "LLM correctly emits ticket__assign with required fields" do
  agent  = AshHarness.Test.TriageAgent
  prompt = "Assign ticket abc-123 to Alice."

  {:ok, calls} =
    AshHarness.Test.LLMHarness.run_one_turn(agent, prompt)

  assert [call] = calls
  assert call.tool_name == "ticket__assign"
  assert call.input.id == "abc-123"
  assert call.input.assigned_to != nil
end
```

## Why this is a separate doc

These tests aren't a benchmark in the τ-bench sense — they don't have
public leaderboards. But they're the difference between an agent that
works on average and an agent that works reliably. Treating them as a
separate concern from the headline benchmark keeps both clear.

## What we *don't* do

- We don't reimplement BFCL. The original BFCL is Python-based and
  oriented around their specific function-call categories. We borrow
  the spirit, not the artifact.
- We don't ship public benchmark numbers from this layer. It's
  internal regression / quality assurance.
