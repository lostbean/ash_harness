# Open Questions

These need answers before or during implementation. Ranked by urgency.

## Must answer before Phase 1

### 1. Verify the `ash_ai` situation

ADR 0010 is based on training-time knowledge of `ash_ai`. Before
publishing the README, check:

- The current feature set of `ash_ai` on GitHub.
- Whether they've added agent-DSL features that overlap heavily.
- Whether the maintainers would be receptive to a contribution path
  for AshHarness's distinguishing features.

If the ecosystem has shifted, revisit the positioning.

### 2. Verify Jido Composer API surface details

Spot-check the following against current `jido_composer` source:

- The exact return shape of `Jido.Composer.Skill.assemble/2`.
- The exact suspension/resume API for HITL.
- Whether `LLMStub` is publicly exposed or test-only.
- The model-string format (`"anthropic:claude-…"`).
- OTel span hierarchy (whether AshHarness can attach attributes to
  the active span without ceremony).

If any of these differ from what `architecture/jido-integration.md`
assumes, update that doc *and* the harness module before
implementation.

### 3. τ-bench current shape

`benchmark/tau-bench-airline-port.md` is sketched from memory. Before
Phase 7, fetch the current τ-bench airline domain:

- Schema (resources, fields).
- Policy document text.
- Task suite JSON.
- Scoring rules.

Update the port doc with the current shape.

## Must answer during Phase 1

### 4. Spark version compatibility

The agent module's `use AshHarness.Agent` macro is a Spark DSL.
Confirm `Spark.Dsl` v2.x's `default_extensions` mechanism still works
the way the spec assumes. If Spark has changed the recommended
pattern, update `layers/03-agent-dsl.md`.

### 5. How do we propagate session into generated `Jido.Action.run/2`?

The dispatch needs `session` from `ctx`. Confirm that
`Jido.Composer.Orchestrator` passes a context map into tool calls
(it should — that's standard). If we need to add a "session
injector" interceptor or use a process dictionary, document and
revise `layers/07-harness-runtime.md`.

## Must answer during Phase 2

### 6. Token estimation tokenizer

`byte_size / 4` is a rough heuristic. Is there a Jido or hex tokenizer
package we should depend on for higher accuracy? `tiktoken` Elixir
ports? Defer if no lightweight option exists.

### 7. What does Ash 3.x return when `Ash.can?` returns `:maybe`?

For renderer pre-filtering, we render actions where `Ash.can?` is
`true` or `:maybe` and exclude `false`. Verify the exact API.

## Must answer during Phase 3

### 8. Resource short-name conflict resolution

If two resources have the same suffix (`MyApp.A.Order` and
`MyApp.B.Order`), the spec says we add `as: "..."` aliases. Confirm:

- Does `Ash.Resource.Info` give us a unique short name we can default
  to? (Probably the last segment.)
- Should the verifier auto-suggest an alias on conflict?

### 9. Generic action input normalization

Generic actions (`action :foo, :map do … end`) have argument
declarations but the dispatch is via `Ash.run_action/2`. Confirm the
canonical input shape and that the schema generator works for them.

### 10. Read action filter parameters

The spec says `:read` actions accept a `filter` map keyed by public
attributes, and we build an `Ash.Query` at execution. Spec out:

- The exact JSON Schema shape for `filter`.
- Operator support (eq, lt, gt, in, between).
- How sort and pagination are exposed (or whether they're separate
  meta-tools).

## Must answer during Phase 4

### 11. Confirmation flow round-trip

The spec assumes `{:halt, ApprovalRequest}` from a `Jido.Action.run/2`
becomes a suspension that the host app handles. Verify with Jido docs
whether `run/2` may return a halt directive or whether we need a
different mechanism.

### 12. How is mutation_count tracked across `run`/`resume`?

When `run/2` halts on a confirmation, the mutation count so far is in
the session. After `resume/2`, the count continues. Verify that this
holds when Jido's checkpointing serializes the session.

### 13. Hot reload behavior

What happens when an agent module recompiles in dev while a session
holds a stale orchestrator reference? Document the recommended pattern
(probably: `Phoenix.CodeReloader` users invalidate sessions on reload).

## Must answer during Phase 5

### 14. OTel span attribute attachment

Confirm `OpenTelemetry.Tracer.set_attributes/1` works inside a Jido
orchestrator's tool-call context — i.e., we can add attributes to the
active span Jido created. If not, we may need to start our own child
span.

### 15. Telemetry event handlers and crash isolation

Test that a buggy user-attached handler doesn't crash the harness.
Document handler-error policy.

## Must answer during Phase 6

### 16. Eval transactional isolation

For ETS, how do we sandbox so scenarios don't pollute each other? Per
test: new ETS table? `Ash.DataLayer.Ets.SandboxTable`? Document.

For Postgres: standard `Ash.Test` setup with `:async`.

### 17. Judge model cost accounting

If qualitative reports run on Anthropic Claude Opus, costs add up
fast for full eval suites. Should we cache judge responses by
(scenario, criterion, agent_response_hash)? Probably yes — design.

## Must answer during Phase 7

### 18. τ-bench user simulator: separate process or in-line?

Multi-turn drives a back-and-forth between agent and user-simulator.
Should the simulator run in a separate Jido session, or be a callback
function? In-line is simpler; separate process is closer to τ-bench's
Python implementation.

### 19. τ-bench scoring parity

τ-bench reports a specific %-score format. Confirm we can produce a
comparable number from gate-pass-rate over scenarios.

## Stretch / v0.2 questions

- Two-tier delegation (structured returns within trust zone): when do
  we have enough eval data to inform the design?
- MCP server: build our own router, or contribute upstream to
  `hermes_mcp`?
- Streaming: surface partial responses through `AshHarness.Harness.run/3`?
- Reflexion-style memory across attempts: needed, or does Repair Loop
  handle the cases that matter?
- Tool composition audit logging: detect "individually authorized;
  composition isn't" patterns?
- Per-tenant agent caching to avoid re-rendering context every session?

## Discussion log markers

When answering, replace the question block with a short answer plus a
date and the source (`docs verified`, `spike`, `interview`). Keep the
question doc as a living artifact through v0.1.0.
