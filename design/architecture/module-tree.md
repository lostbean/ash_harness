# Architecture — Module Tree

The internal layout of AshHarness. All public modules live under
`AshHarness.*`. The mix package is `ash_harness`.

Current layout (v0.1.2). Annotations on lines marked with `# v0.1.x:`
flag deltas from the original design sketch — see "Consolidations
landed in v0.1.x" below.

```text
lib/ash_harness/
├── ash_harness.ex                       # top-level docs, version, info
├── application.ex                       # OTP application; starts SessionSupervisor (v0.1.1)
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
│   │   └── delegate_entry.ex            # %Delegation.DelegateEntry{} — gains :as alias (v0.1.2)
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
│       ├── delegates_use_ash_harness_agent.ex
│       └── delegate_aliases_unique.ex   # v0.1.2: dedupe `as:` aliases
│
├── reachability.ex                      # build/2, reachable_from/2
│
├── context_renderer.ex                  # render/2, render_resource/3 — sections inlined as private fns
├── context_renderer/
│   └── token_estimate.ex                # byte_size / 4 heuristic (only sub-module retained)
│
├── rendered_context.ex                  # %RenderedContext{} struct (4 fields, not 11)
│
├── schema.ex                            # canonical schema derivation
├── schema/
│   ├── canonical.ex                     # %Canonical{} — single source artifact
│   ├── ash_type_mapper.ex               # Ash type → JSON Schema
│   └── render/
│       ├── anthropic.ex                 # canonical → Anthropic input_schema
│       ├── openai.ex                    # canonical → OpenAI parameters
│       └── mcp.ex                       # canonical → MCP inputSchema
│   # validators.ex deferred to v0.2 (JSON Schema sanity checks)
│
├── tool_gen.ex                          # compile-time emitter
├── tool_gen/
│   ├── action_module.ex                 # generate one Jido.Action per Ash action
│   ├── skill_module.ex                  # generate one Jido.Composer.Skill per resource
│   └── orchestrator_module.ex           # v0.1.1: generated per-agent Orchestrator (was on `runtime_dynamic.ex`)
│
├── tool.ex                              # public surface: AshHarness.Tool.dynamic/2 + Tool.t() wrapper
│
├── harness.ex                           # public runtime API: new_session/run/resume/trajectory
├── harness/
│   ├── session.ex                       # %Session{} struct (snapshot)
│   ├── session_agent.ex                 # v0.1.1: supervised GenServer holding mutable per-turn state
│   ├── session_supervisor.ex            # v0.1.1
│   ├── intent.ex                        # %Intent{} struct
│   ├── result.ex                        # %Result{} struct
│   ├── trajectory_entry.ex              # %TrajectoryEntry{} — gains :data field (v0.1.2)
│   ├── orchestrator_factory.ex          # build a Jido orchestrator for an agent
│   ├── load_resource_skill.ex           # progressive-disclosure meta-tool
│   ├── scope_gate.ex                    # validate (resource, action) ∈ scope
│   ├── reasoning_gate.ex                # require_reasoning_for enforcement
│   ├── confirmation_gate.ex             # bridges to Jido ApprovalRequest (named *_gate.ex per convention)
│   ├── budget_gate.ex                   # mutation count enforcement
│   ├── policy_gate.ex                   # Ash.can?/3 wrapper with caching
│   ├── action_executor.ex               # Ash.read/create/update/destroy dispatch
│   ├── generated_action.ex              # shared dispatch entry point invoked by every generated Jido.Action
│   └── repair.ex                        # repair loop (consolidated under harness/, not top-level)
│
├── delegation.ex                        # AshHarness.Delegation — thin re-export
├── delegation/
│   ├── initiate.ex                      # cross-agent boundary crossing (v0.1.2: moved here)
│   ├── result.ex                        # %Result{reply_text, target_trajectory_id, ...} (v0.1.2)
│   └── skill.ex                         # v0.1.2: Jido.Action that exposes delegate(target, question) to the LLM
│
├── eval.ex                              # `use AshHarness.Eval` DSL
├── eval/
│   ├── scenario.ex                      # %Scenario{} struct
│   ├── gate.ex                          # consolidated gate evaluator (covers :resource_state + :invariant)
│   ├── report.ex                        # consolidated report computer (covers :trajectory + :qualitative)
│   ├── runner.ex                        # gate-then-report scenario runner
│   ├── result.ex                        # %EvalResult{} struct
│   ├── sandbox.ex                       # v0.1.1: per-scenario ETS sandbox
│   ├── cassette.ex                      # v0.1.1: req_cassette helper
│   └── judge.ex                         # qualitative judge model integration
│
├── telemetry.ex                         # AshHarness telemetry events + OTel attribute attachment
│
├── errors.ex                            # AshHarness.Errors.classify/1 dispatcher
└── errors/                              # v0.1.2: errors tree populated (seven defexception structs)
    ├── scope_violation.ex
    ├── policy_denied.ex
    ├── validation_failed.ex
    ├── mutation_limit_exceeded.ex
    ├── reasoning_required.ex
    ├── delegation_not_permitted.ex
    └── delegation_depth_exceeded.ex     # v0.1.2: depth-cap struct now part of the tree
```

## Consolidations landed in v0.1.x

| Original design | Actual layout | Why |
| --- | --- | --- |
| `context_renderer/*_section.ex` (8 modules) | `context_renderer.ex` (private fns) + `context_renderer/token_estimate.ex` | Sections share state (actor, agent, reachability) — extracting them adds threading without splitting concerns |
| `repair.ex` at top level + `repair/*` | `harness/repair.ex` (single module) | The repair loop only runs inside the gate pipeline; lives with the harness |
| `delegation.ex` monolithic | `delegation.ex` (re-export) + `delegation/{initiate,result,skill}.ex` | v0.1.2 split for testability and the new Jido.Action skill |
| `harness/confirmation.ex` | `harness/confirmation_gate.ex` | Match the `*_gate.ex` naming convention |
| `eval/gate/*.ex` (per-kind files) | `eval/gate.ex` (single dispatcher) | Per-kind logic is short; one file with a dispatch case is clearer |
| `eval/report/*.ex` (per-kind files) | `eval/report.ex` (single dispatcher) | Same as above |
| `schema/validators.ex` | not implemented | Deferred to v0.2; not a blocker for v0.1.x |
| `tool_gen/runtime_dynamic.ex` | inlined into `tool.ex` | One file, public surface stays at `AshHarness.Tool` |
| `errors/` empty placeholder | seven `defexception` modules (v0.1.2) | Audit-followup populated the tree |

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
