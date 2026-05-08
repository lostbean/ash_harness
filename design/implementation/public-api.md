# Public API Surface (v0.1.0)

This is the function-level contract. Things outside this list are
internal and may change between minor versions.

## Resource extension introspection

```elixir
AshHarness.Resource.Info.description(resource)            :: String.t() | nil
AshHarness.Resource.Info.hints(resource)                  :: [Hint.t()]
AshHarness.Resource.Info.hint_for(resource, action)       :: String.t() | nil
AshHarness.Resource.Info.traversable(resource)            :: [atom()]
AshHarness.Resource.Info.hidden_attributes(resource)      :: [atom()]
AshHarness.Resource.Info.agent_annotated?(resource)       :: boolean()
```

## Domain extension introspection

```elixir
AshHarness.Domain.Info.description(domain)                :: String.t() | nil
AshHarness.Domain.Info.terms(domain)                      :: [Term.t()]
AshHarness.Domain.Info.term_for(domain, word)             :: String.t() | nil
```

## Agent introspection

```elixir
AshHarness.Agent.Info.name(agent)                         :: String.t()
AshHarness.Agent.Info.description(agent)                  :: String.t()
AshHarness.Agent.Info.actor(agent)                        :: any()
AshHarness.Agent.Info.model(agent)                        :: String.t() | nil
AshHarness.Agent.Info.domains(agent)                      :: [module()]
AshHarness.Agent.Info.scope_entries(agent)                :: [ResourceEntry.t()]
AshHarness.Agent.Info.scoped_resources(agent)             :: [module()]
AshHarness.Agent.Info.scoped_actions(agent, resource)     :: [atom()]
AshHarness.Agent.Info.in_scope?(agent, resource, action)  :: boolean()
AshHarness.Agent.Info.confirm_before(agent)               :: [atom()]
AshHarness.Agent.Info.auto_execute(agent)                 :: [atom()]
AshHarness.Agent.Info.confirms_action?(agent, action)     :: boolean()
AshHarness.Agent.Info.strategies(agent)                   :: [Strategy.t()]
AshHarness.Agent.Info.delegates(agent)                    :: [DelegateEntry.t()]
AshHarness.Agent.Info.delegate_for?(agent, target)        :: boolean()
AshHarness.Agent.Info.max_mutations_per_turn(agent)       :: non_neg_integer()
AshHarness.Agent.Info.max_context_tokens(agent)           :: non_neg_integer()
AshHarness.Agent.Info.max_repair_loop_retries(agent)      :: non_neg_integer()
AshHarness.Agent.Info.require_reasoning_for(agent)        :: [atom()]
AshHarness.Agent.Info.reasoning_required?(agent, action)  :: boolean()
AshHarness.Agent.Info.reachability_graph(agent)           :: Reachability.graph()
AshHarness.Agent.Info.tool_list(agent)                    :: [{module(), atom(), Canonical.t()}]
```

## Reachability

```elixir
AshHarness.Reachability.build(agent)                      :: graph()
AshHarness.Reachability.edges_from(graph, source)         :: [edge()]
AshHarness.Reachability.reachable_from(graph, source)     :: [module()]
AshHarness.Reachability.edge_to?(graph, source, dest)     :: boolean()
```

## Context rendering

```elixir
AshHarness.ContextRenderer.render(agent, opts)            :: RenderedContext.t()
AshHarness.ContextRenderer.render_resource(agent, resource, opts)
                                                          :: String.t()
AshHarness.ContextRenderer.resource_summary(agent, resource)
                                                          :: String.t()
```

## Tool generation

```elixir
AshHarness.Tool.dynamic(name, opts)                       :: Jido.Action.t()
AshHarness.Schema.Render.Anthropic.render(canonical)      :: map()
AshHarness.Schema.Render.OpenAI.render(canonical)         :: map()
AshHarness.Schema.Render.MCP.render(canonical)            :: map()
```

## Harness runtime

```elixir
AshHarness.Harness.new_session(agent, opts)               :: Session.t()
AshHarness.Harness.run(session, user_message, opts)       ::
    {:ok, String.t(), Session.t()}
  | {:halt, ApprovalRequest.t(), Session.t()}
  | {:error, term(), Session.t()}
AshHarness.Harness.resume(session, approval_response)     ::
    {:ok, String.t(), Session.t()}
  | {:halt, ApprovalRequest.t(), Session.t()}
  | {:error, term(), Session.t()}
AshHarness.Harness.trajectory(session)                    :: [TrajectoryEntry.t()]
AshHarness.Harness.mutation_count(session)                :: non_neg_integer()
```

## Repair loop

```elixir
AshHarness.Harness.Repair.format_feedback(error)          :: String.t()
AshHarness.Harness.Repair.retryable?(error)               :: boolean()
```

## Delegation

```elixir
AshHarness.Delegation.initiate(caller_session, target_agent, question, opts) ::
    {:ok, String.t(), Session.t(), [TrajectoryEntry.t()]}
  | {:error, :delegation_not_permitted}
  | {:error, :delegation_depth_exceeded}
  | {:error, term()}
```

## Evaluation

```elixir
AshHarness.Eval.Runner.run(scenario, opts)                :: Result.t()
AshHarness.Eval.Runner.run_all(eval_module, opts)         :: [Result.t()]
```

## Telemetry

The full event catalog lives in `layers/11-telemetry.md`. Event names
are part of the public API surface; metadata is part of the public API;
measurements are stable across minor versions.

## Stability commitments

For v0.1.x:

- The introspection module function signatures are stable.
- Telemetry event names and required metadata fields are stable.
- The DSL surface (sections, entities, schema keys) is stable.
- Internal modules (transformers, verifiers, gate impls) may change.

For v0.2:

- Additive changes to DSL (new optional keys) without breaking existing
  agents.
- Possibly: `streaming`, `two-tier delegation`, `pairwise qualitative`
  added.
- Potentially-breaking changes are surfaced in CHANGELOG with migration
  notes.

## What's intentionally *not* in the public API

- The session struct's internal layout. Treat it as opaque except via
  the `trajectory/1` and `mutation_count/1` accessors.
- The intent struct. Constructed inside generated tools.
- The orchestrator factory. Use `new_session/2`, not the factory.
- Internal Jido orchestrator state inside the session. Reach into Jido
  directly if you need it, accepting the coupling.
