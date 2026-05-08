# Test Strategy

Tests are organized by layer. Each layer has unit tests for pure logic
and integration tests through the layer above.

## Test resources

A canonical set of resources lives at `test/support/resources/`. They
exercise:

- Multiple action types (`:read`, `:create`, `:update`, `:destroy`,
  generic).
- Validations and policies.
- All the Ash types we promise to map (see
  `benchmark/bfcl-schema-tests.md` table).
- Cyclic relationships (Project ↔ Ticket).
- Self-referential relationships (Ticket parent_ticket).

```text
test/support/resources/
├── domain.ex              # AshHarness.Test.Domain (with terms)
├── project.ex             # has_many tickets
├── ticket.ex              # belongs_to project, has_many comments,
│                          # belongs_to assignee (Member),
│                          # belongs_to parent_ticket (self)
├── comment.ex             # belongs_to ticket
├── member.ex              # has_many tickets (as assignee)
└── order.ex               # for type-coverage; decimal, array, map
```

The `AshHarness.Test.Domain` is the multi-purpose test domain that
all tests share. It's Ash-only (no AshHarness extension) at the start;
specific tests may attach the `AshHarness.Resource` extension via
`use Ash.Resource, extensions: [AshHarness.Resource]`.

## Test agents

```text
test/support/agents/
├── triage_agent.ex        # the canonical example
├── read_only_agent.ex     # auto_execute everything; no mutations
├── delegating_agent.ex    # has delegates_to entries
├── empty_scope_agent.ex   # for verifier-failure tests (compile fails)
└── conflicting_aliases_agent.ex  # for resource-name-conflict tests
```

## Test data layer

Default to `Ash.DataLayer.Ets`. Each test sets up its own ETS table
(or uses Ash sandbox helpers). No Postgres in unit tests.

For AshPostgres-specific tests (Phase 8), a separate `MIX_ENV=postgres`
target spins up Docker.

## Test categories

### Unit tests (per layer)

| Module | Test file |
| --- | --- |
| `AshHarness.Resource` | `test/ash_harness/resource_test.exs` |
| `AshHarness.Domain` | `test/ash_harness/domain_test.exs` |
| `AshHarness.Agent` | `test/ash_harness/agent_test.exs` |
| Verifiers | `test/ash_harness/agent/verifiers/*_test.exs` |
| `AshHarness.Reachability` | `test/ash_harness/reachability_test.exs` |
| `AshHarness.Schema.Canonical` | `test/ash_harness/schema/canonical_test.exs` |
| Renderers | `test/ash_harness/schema/render/{anthropic,openai,mcp}_test.exs` |
| `AshHarness.ContextRenderer` | `test/ash_harness/context_renderer_test.exs` |
| `AshHarness.ToolGen` | `test/ash_harness/tool_gen_test.exs` |
| Gates | `test/ash_harness/harness/{scope,reasoning,budget,policy}_gate_test.exs` |
| `AshHarness.Harness.ActionExecutor` | `test/ash_harness/harness/action_executor_test.exs` |
| `AshHarness.Harness.Repair` | `test/ash_harness/harness/repair_test.exs` |
| `AshHarness.Delegation` | `test/ash_harness/delegation_test.exs` |

### Integration tests (multi-layer)

| File | Coverage |
| --- | --- |
| `test/ash_harness/harness_integration_test.exs` | full intent → result through all gates |
| `test/ash_harness/end_to_end_test.exs` | LLMStub → orchestrator → gates → action → response |
| `test/ash_harness/delegation_integration_test.exs` | A delegates to B; A only sees text |

### Compile-error tests

Verifier failures must produce specific error messages. We test these by
attempting to compile a known-bad agent at test time:

```elixir
test "verifier raises when scope action does not exist" do
  assert_raise CompileError,
               ~r/Action :nope does not exist on AshHarness.Test.Ticket/,
               fn ->
                 Code.eval_string("""
                 defmodule BadAgent do
                   use AshHarness.Agent, domains: [AshHarness.Test.Domain]
                   identity do … end
                   scope do
                     resource AshHarness.Test.Ticket, do: actions: [:nope]
                   end
                 end
                 """)
               end
end
```

(In practice we use a helper to encapsulate the eval-and-rescue.)

### Schema tests

Per `benchmark/bfcl-schema-tests.md`:

- Type-coverage matrix is enforced — adding a type to test resources
  without a matching mapper test fails CI.
- Round-trip tests prove rendered → parse → intent works.
- LLMStub-driven test for one-turn tool-call accuracy on the test
  agent.

### Eval framework tests

`test/ash_harness/eval/runner_test.exs`:

- Scenario with a gate that passes — passes.
- Scenario with a gate that fails — fails.
- Scenario with a passing gate but failing trajectory report — passes
  with diagnostic surfaced.
- Scenario with qualitative criterion below threshold — passes with
  diagnostic surfaced.

## LLM mocking

Use `Jido.Composer.LLMStub` (provided by `jido_composer`). It returns
a sequence of pre-programmed responses, including tool calls and final
messages. This lets us test:

- Single-turn tool calls.
- Multi-turn loops with intermediate tool calls.
- Repair loop (LLM emits invalid input, harness formats error, LLM
  retries with corrected input).

For tests that genuinely need a live LLM (judge model, integration
benchmark), they're gated behind `@tag :integration` and only run with
`MIX_ENV=integration` and an API key in env.

## Coverage targets

- **Layer-1 modules** (Resource/Domain/Agent extensions, Reachability,
  Schema): aim for 95%+ line coverage. Pure logic; no excuse not to.
- **Layer-2 modules** (ContextRenderer, ToolGen, Harness gates): 90%+.
- **Layer-3 modules** (orchestration, delegation, eval runner): 80%+;
  some paths require integration tests.
- **Compile-time generators**: cover all branches via at-test-time
  module compilation.

## CI

GitHub Actions matrix:

- `mix test` (default — ETS only).
- `MIX_ENV=postgres mix test` (Postgres-tagged tests).
- `MIX_ENV=integration mix test` (real LLM; runs nightly with budget
  caps; not on every PR).
- `mix format --check-formatted`.
- `mix credo --strict`.
- `mix dialyzer`.

## Test naming convention

```
test "<verb phrase describing the behavior>", <opts> do
  # Arrange
  # Act
  # Assert
end
```

Examples:

- `test "rejects scope with action not on resource"`
- `test "renders hidden attributes as omitted"`
- `test "increments mutation count on successful update"`
- `test "format_feedback returns retryable=true for validation errors"`

Avoid:

- Naming after the function (`test "Module.fn/1"`).
- Naming after the bug ("test #42").

## Philosophy

- **Test the contract, not the implementation.** Test that
  `Reachability.build/1` produces the right edges, not that it uses a
  particular traversal algorithm.
- **Resource fixtures are shared.** Don't define a one-off resource in
  a test if a shared one fits.
- **Snapshot the rendered output.** ContextRenderer tests use
  fixture-comparison; intentional output changes update fixtures.
- **Compile-time failures are first-class.** A surprising compile
  error is a worse user experience than a wrong runtime — verify each
  expected message.
