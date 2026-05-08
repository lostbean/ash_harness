# Architecture — Module Tree

The internal layout of AshHarness. All public modules live under
`AshHarness.*`. The mix package is `ash_harness`.

```text
lib/ash_harness/
├── ash_harness.ex                       # top-level docs, version, info
│
├── resource.ex                          # Spark.Dsl.Extension — agent_annotations
├── resource/
│   ├── hint.ex                          # %Hint{} struct
│   ├── info.ex                          # Spark-generated introspection
│   ├── transformer.ex                   # persist hints/traversable into DSL state
│   └── verifier.ex                      # validate hints/traversable/hidden_attributes
│
├── domain.ex                            # Spark.Dsl.Extension — agent_domain
├── domain/
│   ├── term.ex                          # %Term{} struct
│   ├── info.ex
│   └── verifier.ex
│
├── agent.ex                             # `use AshHarness.Agent` macro + DSL
├── agent/
│   ├── dsl.ex                           # Spark.Dsl.Extension entries
│   ├── identity.ex                      # %Identity{} struct
│   ├── scope/
│   │   └── resource_entry.ex            # %Scope.ResourceEntry{} struct
│   ├── behavior/
│   │   └── strategy.ex                  # %Behavior.Strategy{} struct
│   ├── delegation/
│   │   └── delegate_entry.ex            # %Delegation.DelegateEntry{} struct
│   ├── info.ex                          # introspection
│   ├── transformers/
│   │   ├── compute_reachability.ex      # build & persist reachability graph
│   │   └── compute_tool_set.ex          # persist canonical tool list
│   └── verifiers/
│       ├── scope_resources_in_domains.ex
│       ├── scope_actions_exist.ex
│       ├── confirm_before_in_scope.ex
│       ├── auto_execute_in_scope.ex
│       ├── reasoning_actions_in_scope.ex
│       └── delegates_use_ash_harness_agent.ex
│
├── reachability.ex                      # build/2, reachable_from/2
│
├── context_renderer.ex                  # render/2, render_resource/3
├── context_renderer/
│   ├── identity_section.ex
│   ├── domain_section.ex
│   ├── resource_section.ex
│   ├── traversal_section.ex
│   ├── strategy_section.ex
│   ├── delegation_section.ex
│   ├── constraints_section.ex
│   └── token_estimate.ex
│
├── schema.ex                            # canonical schema derivation
├── schema/
│   ├── canonical.ex                     # %Canonical{} — single source artifact
│   ├── ash_type_mapper.ex               # Ash type → JSON Schema
│   ├── render/
│   │   ├── anthropic.ex                 # canonical → Anthropic input_schema
│   │   ├── openai.ex                    # canonical → OpenAI parameters
│   │   └── mcp.ex                       # canonical → MCP inputSchema
│   └── validators.ex                    # JSON Schema sanity checks
│
├── tool_gen.ex                          # compile-time emitter
├── tool_gen/
│   ├── action_module.ex                 # generate one Jido.Action per Ash action
│   ├── skill_module.ex                  # generate one Jido.Composer.Skill per resource
│   └── runtime_dynamic.ex               # AshHarness.Tool.dynamic/2
│
├── tool.ex                              # public surface: AshHarness.Tool.dynamic/2 etc.
│
├── harness.ex                           # public runtime API: new_session/run/confirm
├── harness/
│   ├── session.ex                       # %Session{} struct
│   ├── intent.ex                        # %Intent{} struct
│   ├── result.ex                        # %Result{} struct
│   ├── trajectory_entry.ex              # %TrajectoryEntry{} struct
│   ├── orchestrator_factory.ex          # build a Jido orchestrator for an agent
│   ├── scope_gate.ex                    # validate (resource, action) ∈ scope
│   ├── policy_gate.ex                   # Ash.can?/3 wrapper with caching
│   ├── budget_gate.ex                   # mutation count enforcement
│   ├── confirmation.ex                  # bridges to Jido ApprovalRequest
│   ├── reasoning_gate.ex                # require_reasoning_for enforcement
│   └── action_executor.ex               # Ash.read/create/update/destroy dispatch
│
├── repair.ex                            # repair loop (formerly Ralph Loop)
├── repair/
│   ├── format_feedback.ex
│   └── retryable.ex
│
├── delegation.ex                        # AshHarness.Delegation
├── delegation/
│   ├── initiate.ex                      # cross-agent boundary crossing
│   └── result.ex                        # delegate's text response wrapper
│
├── eval.ex                              # `use AshHarness.Eval` DSL
├── eval/
│   ├── dsl.ex
│   ├── scenario.ex                      # %Scenario{} struct
│   ├── gate/
│   │   ├── resource_state.ex
│   │   └── invariant.ex                 # custom Elixir gate
│   ├── report/
│   │   ├── trajectory.ex
│   │   └── qualitative.ex
│   ├── runner.ex                        # gate-then-report scenario runner
│   └── result.ex                        # %EvalResult{} struct
│
├── telemetry.ex                         # AshHarness telemetry events
│
└── errors/
    ├── scope_violation.ex
    ├── policy_denied.ex
    ├── validation_failed.ex
    ├── mutation_limit_exceeded.ex
    ├── reasoning_required.ex
    └── delegation_not_permitted.ex
```

## Compile-time vs runtime

| Module group | When it runs |
| --- | --- |
| `AshHarness.Resource.Transformer/Verifier` | compile time of resources |
| `AshHarness.Domain.Verifier` | compile time of domains |
| `AshHarness.Agent.Transformers.*` | compile time of agents (after Resource/Domain) |
| `AshHarness.Agent.Verifiers.*` | compile time, after all transformers |
| `AshHarness.ToolGen.ActionModule` / `SkillModule` | compile time of agents |
| `AshHarness.Schema.Canonical` derivation | compile time of agents |
| `AshHarness.ContextRenderer` | runtime (per session, optionally cached) |
| `AshHarness.Harness.*` gates and executors | runtime (per intent) |
| `AshHarness.Repair` | runtime |
| `AshHarness.Eval.Runner` | test/CI time |

## What's *not* a module

These are deliberately not separate modules:

- **No `AshHarness.LLM.Adapter` behaviour.** Jido owns provider transport.
  We don't need our own behaviour layer.
- **No standalone `AshHarness.Compaction`.** Jido handles compaction; we
  may add a strategy hook later but don't ship our own engine. (See ADR
  0001 for the Jido boundary.)
- **No `AshHarness.LLM.Mock`.** For tests we use Jido's `LLMStub`.
- **No `AshHarness.Tool.Schema` separate from `AshHarness.Schema`.** One
  schema module, multiple renderers.

## File-naming conventions

- `*_entry.ex` for DSL entity target structs (e.g., `ResourceEntry`).
- `*_gate.ex` for harness pre-execution gates that can refuse an intent.
- `transformers/` subdirectories for Spark transformers.
- `verifiers/` subdirectories for Spark verifiers.
- `info.ex` is the Spark-generated introspection module per extension.
- `render/<format>.ex` for schema renderers.
