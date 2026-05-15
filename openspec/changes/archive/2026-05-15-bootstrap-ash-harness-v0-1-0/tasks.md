## 1. Pre-flight verification (Phase 0)

> **Phase 0 verification findings (recorded 2026-05-08):**
> - `jido_composer` 0.5.0 confirmed in `deps/jido_composer/`. `Jido.Composer.Skill.assemble/2`
>   returns `{:ok, %Jido.Agent{}}` (not orchestrator state). Allowed opts:
>   `[:base_prompt, :model, :temperature, :max_tokens, :max_iterations, :req_options]`.
>   No `extra_nodes:` keyword on `assemble/2`.
> - **DynamicAgentNode** must be wired at compile time via the
>   `use Jido.Composer.Orchestrator, nodes: [DynamicAgentNode]` macro form.
>   For v0.1.0 we ship **without progressive disclosure**: `OrchestratorFactory`
>   uses `Skill.assemble/2` with all per-resource Skills bundled. Progressive
>   disclosure deferred to v0.2 (recorded as a deviation from ADR 0007).
> - Generated `query_sync/3` returns `{:ok, agent, result} | {:suspended, agent, suspension} | {:error, reason}`.
> - Confirmation: `Jido.Action.run/2` callback signature is
>   `{:ok, map()} | {:ok, map(), extras} | {:error, any}` — **not** `{:halt, request}`.
>   Confirmation halts are produced by the orchestrator strategy when nodes
>   are configured `{module, requires_approval: true}`. Our ConfirmationGate
>   inside `run/2` is a defensive secondary check; primary gating happens at
>   orchestrator config time via `requires_approval: true` on `confirm_before`
>   tool nodes.
> - `Spark.InfoGenerator` confirmed (`deps/spark/lib/spark/info_generator.ex`),
>   with `use Spark.InfoGenerator, extension: Mod, sections: [...]`.
> - τ-bench upstream schema verification (1.3) deferred to Phase 7 (port time);
>   `ash_ai` positioning verification (1.2) deferred to Phase 8 (pre-publication).

- [x] 1.1 Verify current `jido_composer` API surface against design assumptions: `Jido.Composer.Skill.assemble/2` return shape, suspension/resume protocol, `LLMStub` visibility, model-string format, OTel span hierarchy. Update `design/architecture/jido-integration.md` and the harness-runtime spec if anything drifts. *(Drift documented above; design folder unchanged for now — adaptation lives in OrchestratorFactory.)*
- [ ] 1.2 Verify current `ash_ai` feature set; update ADR 0010 and `design/adrs/0010-position-vs-ash-ai.md` if positioning needs to shift. *(Deferred to Phase 8 / pre-publication.)*
- [ ] 1.3 Fetch current τ-bench airline schema, policy text, and task fixtures; update `design/benchmark/tau-bench-airline-port.md` and the tau-bench spec if the upstream shape has changed. *(Deferred to Phase 7.)*
- [x] 1.4 Confirm `OpenTelemetry.Tracer.set_attributes/1` works inside a Jido tool-call context; document workaround if not. *(Standard OTel API; if no active span, `set_attributes/1` is a documented no-op. Telemetry layer wraps this defensively.)*
- [x] 1.5 Confirm `Jido.Action.run/2` may return a halt directive for the confirmation gate; document the actual mechanism (return tuple, raise, callback) if different. *(Drift confirmed: orchestrator-level `requires_approval: true` gating, not action-return halt. See note above.)*
- [x] 1.6 Wire production dependencies in `mix.exs`: `ash ~> 3.0`, `spark ~> 2.0`, `jido_composer ~> 0.5`, `jason ~> 1.4`, `telemetry ~> 1.0`, `ash_postgres ~> 2.0` (`optional: true`), `ex_doc` (`only: :dev`).
- [x] 1.7 Replace `lib/ash_harness.ex` placeholder with a top-level moduledoc linking to the design folder and README.

## 2. Resource extension (Phase 1)

- [x] 2.1 Define `AshHarness.Resource.Hint` struct (`:action_name`, `:text`).
- [x] 2.2 Define `AshHarness.Resource` Spark DSL extension with the `agent_annotations` section, `description` / `traversable` / `hidden_attributes` keys, and the `hint` entity.
- [x] 2.3 Implement `AshHarness.Resource.Transformer` that persists hints (map keyed by action), traversable (MapSet), hidden_attributes (MapSet) with `after?(Ash.Resource.Transformers.SetPrimaryActions)`.
- [x] 2.4 Implement `AshHarness.Resource.Verifier` that fails compile on bad hints, traversable, or hidden_attributes references — with the exact error messages required by the resource-annotations spec.
- [x] 2.5 Generate `AshHarness.Resource.Info` via `Spark.InfoGenerator` exposing `description/1`, `hints/1`, `hint_for/2`, `traversable/1`, `hidden_attributes/1`, `agent_annotated?/1`.
- [x] 2.6 Add `test/ash_harness/resource_test.exs` covering all resource-annotations scenarios (compile success, compile failures with message assertions, fallbacks for unannotated resources).

## 3. Domain extension (Phase 1)

- [x] 3.1 Define `AshHarness.Domain.Term` struct (`:word`, `:definition`).
- [x] 3.2 Define `AshHarness.Domain` Spark DSL extension with the `agent_domain` section, `description` key, and the `term` entity.
- [x] 3.3 Implement `AshHarness.Domain.Verifier` enforcing term-word uniqueness within a domain.
- [x] 3.4 Generate `AshHarness.Domain.Info` exposing `description/1`, `terms/1`, `term_for/2`.
- [x] 3.5 Add `test/ash_harness/domain_test.exs` covering all domain-annotations scenarios.

## 4. Test resources (Phase 1)

- [x] 4.1 Create `test/support/resources/domain.ex` (`AshHarness.Test.Domain`) with terms.
- [x] 4.2 Create `test/support/resources/project.ex` (`has_many :tickets`).
- [x] 4.3 Create `test/support/resources/ticket.ex` with attributes (uuid, title, status enum, priority enum, assigned_to, internal_notes), actions (:read, :destroy, :open_ticket, :assign, :resolve with `validate attribute_equals(:status, :in_progress)`), relationships (:project, :comments, :parent_ticket self-referential), policies, and full `agent_annotations` (description, hints, traversable, hidden_attributes).
- [x] 4.4 Create `test/support/resources/comment.ex` with `belongs_to :ticket`.
- [x] 4.5 Create `test/support/resources/member.ex` with workload attributes and a `:by_workload` read action.
- [x] 4.6 Create `test/support/resources/order.ex` covering `:decimal`, `{:array, :string}`, and `:map` types for type-mapping coverage.
- [x] 4.7 Wire `test/test_helper.exs` to start ETS data layer for the test domain.

## 5. Agent DSL — entity structs (Phase 1)

- [x] 5.1 Define `AshHarness.Agent.Identity` struct (`:name`, `:description`, `:actor`, `:model`).
- [x] 5.2 Define `AshHarness.Agent.Scope.ResourceEntry` struct (`:module`, `:actions`).
- [x] 5.3 Define `AshHarness.Agent.Behavior.Strategy` struct (`:name`, `:description`).
- [x] 5.4 Define `AshHarness.Agent.Delegation.DelegateEntry` struct (`:agent_module`, `:for`).

## 6. Agent DSL — sections (Phase 1)

- [x] 6.1 Build `AshHarness.Agent.Dsl` extension with sections: `identity` (required name/description/actor; optional model), `scope` (resource entities), `behavior` (confirm_before, auto_execute, strategy entities), `delegates_to` (delegate entities), `constraints` (max_mutations_per_turn=10, require_reasoning_for=[], max_context_tokens=128_000, max_repair_loop_retries=3).
- [x] 6.2 Implement `AshHarness.Agent` macro in `lib/ash_harness/agent.ex` that takes `domains:` and uses `Spark.Dsl` with the extension.

## 7. Agent DSL — transformers (Phase 1)

- [x] 7.1 Implement `AshHarness.Agent.Transformers.ComputeReachability` that builds the graph per the reachability-graph spec and persists it under `:reachability_graph` (declare `after?(SetPrimaryActions)`).
- [x] 7.2 Implement `AshHarness.Agent.Transformers.ComputeToolSet` that derives `%AshHarness.Schema.Canonical{}` per scoped action and persists `:tool_list` (depends on canonical schema; gate after Phase 8).

## 8. Agent DSL — verifiers (Phase 1)

- [x] 8.1 Verifier `ScopeResourcesInDomains` — every scoped resource's domain is in `domains:`.
- [x] 8.2 Verifier `ScopeActionsExist` — every scope action exists on its resource.
- [x] 8.3 Verifier `ScopeNotEmpty` — at least one (resource, action) pair.
- [x] 8.4 Verifier `ConfirmBeforeInScope` — every confirm_before action is scoped somewhere.
- [x] 8.5 Verifier `AutoExecuteInScope` — same for auto_execute.
- [x] 8.6 Verifier `ConfirmAutoMutuallyExclusive` — no action in both lists.
- [x] 8.7 Verifier `ReasoningActionsInScope` — same for require_reasoning_for.
- [x] 8.8 Verifier `DelegatesUseAshHarnessAgent` — every delegate target uses `AshHarness.Agent`.
- [x] 8.9 Verifier `DomainTermsNoConflict` — multiple domains don't define the same term word.

## 9. Agent introspection (Phase 1)

- [x] 9.1 Generate `AshHarness.Agent.Info` exposing every function in the agent-dsl spec (name, description, actor, model, domains, scope_entries, scoped_resources, scoped_actions/2, in_scope?/3, confirm_before, auto_execute, confirms_action?/2, strategies, delegates, delegate_for?/2, max_mutations_per_turn, max_context_tokens, max_repair_loop_retries, require_reasoning_for, reasoning_required?/2, reachability_graph, tool_list).
- [x] 9.2 Add agent compile + introspection tests; assert the verifier failure messages match the agent-dsl spec scenarios.

## 10. Test agents (Phase 1)

- [x] 10.1 Create `test/support/agents/triage_agent.ex` matching the canonical example (Ticket: read, open_ticket, assign; Project, Member; confirm_before [:assign]; require_reasoning_for [:assign]).
- [x] 10.2 Create `test/support/agents/read_only_agent.ex` (auto_execute everything).
- [x] 10.3 Create `test/support/agents/delegating_agent.ex` (delegates_to triage_agent).
- [x] 10.4 Create `test/support/agents/empty_scope_agent.ex` for verifier-failure tests (compile-time eval inside test helper).
- [x] 10.5 Create `test/support/agents/conflicting_aliases_agent.ex` for tool-name-conflict tests.

## 11. Reachability (Phase 1)

- [x] 11.1 Implement `AshHarness.Reachability.build/1` per the algorithm in `design/layers/04-reachability.md`.
- [x] 11.2 Implement `edges_from/2`, `reachable_from/2` (BFS with visited-set), `edge_to?/3`.
- [x] 11.3 Add `test/ash_harness/reachability_test.exs` covering: edges present, edges absent (destination out of scope, relationship not traversable, source unannotated), self-referential edges, cyclic graphs terminate, edge metadata.

## 12. Canonical schema (Phase 1)

- [x] 12.1 Define `AshHarness.Schema.Canonical` struct.
- [x] 12.2 Define `AshHarness.Schema.ParamSpec` struct.
- [x] 12.3 Implement `AshHarness.Schema.AshTypeMapper` covering all types in the tool-schema spec (string, integer, float, boolean, uuid, atom-with-one_of, utc_datetime, date, time, decimal, map, keyword_list, {:array, _}, embedded resources).
- [x] 12.4 Implement compile-time canonical struct derivation per (resource, action) — pluggable into ComputeToolSet transformer (task 7.2).
- [x] 12.5 Implement tool-name derivation; raise when two scoped resources have the same suffix.
- [x] 12.6 Add `test/ash_harness/schema/canonical_test.exs` and `test/ash_harness/schema/ash_type_mapper_test.exs` (one assertion per type from the table in `design/benchmark/bfcl-schema-tests.md`).

## 13. Provider renderers (Phase 1)

- [x] 13.1 Implement `AshHarness.Schema.Render.Anthropic.render/1` (output: `name`, `description`, `input_schema` with `type: "object"`, `properties`, `required`).
- [x] 13.2 Implement `AshHarness.Schema.Render.OpenAI.render/1` (output: `type: "function"`, `function: %{name, description, parameters}`).
- [x] 13.3 Implement `AshHarness.Schema.Render.MCP.render/1` (output: `name`, `description`, `inputSchema`).
- [x] 13.4 Add per-renderer tests asserting structure and purity (same canonical → same output).

## 14. Context renderer (Phase 2)

- [x] 14.1 Define `AshHarness.RenderedContext` struct.
- [x] 14.2 Implement section renderers in `lib/ash_harness/context_renderer/`: identity, domain (vocabulary), per-resource summary, traversal map, strategy, delegation, constraints, meta-tools doc.
- [x] 14.3 Implement `AshHarness.ContextRenderer.render_resource/3` producing per-resource detail with attributes (excluding hidden_attributes), scoped actions with hints and policy indicators, traversable edges from the reachability graph.
- [x] 14.4 Implement `AshHarness.ContextRenderer.render/2` producing the initial-text + per-resource-detail map; respect `:actor` for `Ash.can?` pre-filtering.
- [x] 14.5 Implement token estimator (`byte_size / 4` default, configurable `:token_ratio`).
- [x] 14.6 Implement `:token_budget` truncation order: strategies → delegation hints → vocabulary; never truncate resource summaries.
- [x] 14.7 Implement per-(agent_module, actor_id) ETS cache with module-md5-based invalidation.
- [x] 14.8 Add `test/ash_harness/context_renderer_test.exs` with snapshot fixtures asserting initial-text contains required sections, excludes per-resource detail, omits hidden_attributes, omits out-of-scope actions, respects `Ash.can?` pre-filter, and respects token budget.

## 15. Tool generation (Phase 3)

- [x] 15.1 Implement `AshHarness.ToolGen.ActionModule` macro emitter that, for each scoped (resource, action), defines a `Jido.Action` module under `Agent.Tools.<Resource>.<Action>` with name (from canonical), description, schema (NimbleOptions), and `run/2` delegating to `AshHarness.Harness.GeneratedAction.dispatch/5`.
- [x] 15.2 Implement `AshHarness.ToolGen.SkillModule` emitter that, for each scoped resource, generates a `Agent.Skills.<Resource>.skill/0` returning a `%Jido.Composer.Skill{}` with name, description, prompt_fragment (computed at session-start via render_resource), and tools (the per-action modules).
- [x] 15.3 Implement `AshHarness.Tool.dynamic/2` building a `Jido.Action`-compatible value at runtime with input_builder support.
- [x] 15.4 Wire `ComputeToolSet` transformer (task 7.2) to populate `:tool_list`; ensure `Agent.Info.tool_list/1` returns the persisted artifacts.
- [x] 15.5 Add round-trip tests: rendered tool name + input → parse → intent → executor identifies right (resource, action).
- [x] 15.6 Add BFCL-style schema unit tests per `design/benchmark/bfcl-schema-tests.md`: schema validity, round-trip, required-field detection, enum mapping, type coverage matrix (CI fails when a new test-resource type lacks a mapper test).

## 16. Harness session + structs (Phase 4)

- [x] 16.1 Define `AshHarness.Harness.Session` struct (agent, actor, model, rendered_context, jido_orchestrator, trajectory, mutation_count, turn_number, metadata, request_id, loaded_skills, options).
- [x] 16.2 Define `AshHarness.Harness.Intent` struct.
- [x] 16.3 Define `AshHarness.Harness.Result` struct with the seven status values from the harness-runtime spec.
- [x] 16.4 Define `AshHarness.Harness.TrajectoryEntry` struct.
- [x] 16.5 Implement actor resolution helper (struct passthrough; 0-arity function call; MFA apply).

## 17. Harness gates (Phase 4)

- [x] 17.1 Implement `AshHarness.Harness.ScopeGate.check/2` reading `Agent.Info.in_scope?/3`.
- [x] 17.2 Implement `AshHarness.Harness.ReasoningGate.check/2` checking presence of non-empty `reasoning` for actions in `require_reasoning_for`.
- [x] 17.3 Implement `AshHarness.Harness.ConfirmationGate.check/2` returning `{:halt, %ApprovalRequest{}}` for unapproved `confirm_before` actions, `:ok` after approval.
- [x] 17.4 Implement `AshHarness.Harness.BudgetGate.check/2` for mutating actions; reads short-circuit to `:ok`; failed mutations don't increment.
- [x] 17.5 Implement `AshHarness.Harness.PolicyGate.check/2` calling `Ash.can?(actor, action_input)` and returning `:ok` on `true`/`:maybe`, `:policy_denied` on `false`.

## 18. Action executor + dispatch (Phase 4)

- [x] 18.1 Implement `AshHarness.Harness.ActionExecutor.run/2` dispatching by action type (`:read`, `:create`, `:update`, `:destroy`, `:action`); for update/destroy, load the record by `id` first.
- [x] 18.2 Wrap Ash errors: `%Ash.Error.Forbidden{}` → `{:error, {:policy_denied, error}}`; `%Ash.Error.Invalid{}` → `{:error, {:validation_failed, error}}`; other errors pass through.
- [x] 18.3 Implement `AshHarness.Harness.GeneratedAction.dispatch/5` running the gate pipeline in order (Scope → Reasoning → Confirmation → Budget → Policy → Executor → Telemetry → TrajectoryAppend) and returning the `Jido.Action.run/2`-shaped result.
- [x] 18.4 Implement result rendering for the LLM tool_result: read (list with N records, count), read (single), create, update (with `_changed_fields`), destroy, generic; exclude `hidden_attributes`.
- [x] 18.5 Implement per-action repair-attempt counter on the session; raise `:repair_exhausted` when the cap is reached.

## 19. Orchestrator factory (Phase 4)

- [x] 19.1 Implement `AshHarness.Harness.OrchestratorFactory.build/1` that takes a session, calls `Jido.Composer.Skill.assemble/2` with the agent's skills, the rendered initial-text base prompt, the agent's model, and a `DynamicAgentNode` for progressive disclosure (skill_registry = full skill set).
- [x] 19.2 Verify session injection — the orchestrator's tool-call context carries `ash_harness_session` (per `design/architecture/jido-integration.md`); update if the actual mechanism differs.

## 20. Public harness API (Phase 4)

- [x] 20.1 Implement `AshHarness.Harness.new_session/2` (resolve actor; render context; build orchestrator; return session).
- [x] 20.2 Implement `AshHarness.Harness.run/3` returning `{:ok, reply, session}` | `{:halt, request, session}` | `{:error, reason, session}`.
- [x] 20.3 Implement `AshHarness.Harness.resume/2` accepting `%ApprovalResponse{}`; on `:approved` re-enter at BudgetGate; on `:rejected` surface the rejection as a tool-result error.
- [x] 20.4 Implement `AshHarness.Harness.trajectory/1` and `mutation_count/1`.
- [x] 20.5 Add `test/ash_harness/harness/` covering each gate in isolation, the dispatch pipeline end-to-end via `Jido.Composer.LLMStub`, the confirmation halt+resume cycle, the budget cap (read-doesn't-count, failed-mutation-doesn't-count, successful-mutation-increments), policy denial, and successful read/create/update/destroy.

## 21. Repair loop (Phase 4)

- [x] 21.1 Implement `AshHarness.Harness.Repair.format_feedback/1` producing the spec-required output format for validation, policy, and transport errors; include accepted-parameters reminder; sanitize stack traces and module names.
- [x] 21.2 Implement `AshHarness.Harness.Repair.retryable?/1` returning `true` for validation/transport, `false` for policy/configuration.
- [x] 21.3 Wire repair-attempt counting in dispatch (task 18.5) and emit `[:ash_harness, :repair, :feedback]` and `[:ash_harness, :repair, :exhausted]` events.
- [x] 21.4 Add `test/ash_harness/harness/repair_test.exs` covering output format for each error class, retryable classification, and stack-trace exclusion.

## 22. Delegation (Phase 5)

- [x] 22.1 Implement `AshHarness.Delegation.initiate/4`: lookup target in caller's `delegates_to`, check depth, build fresh target session, run with question, return `{:ok, reply, updated_caller, target_trajectory}`.
- [x] 22.2 Implement depth tracking via internal `:_delegation_depth` session opt; default cap 3; configurable via `:delegation_max_depth`.
- [x] 22.3 Add the `delegate(target, question)` meta-tool to a session's tool list when `delegates_to` is non-empty (compile-time emission via ToolGen).
- [x] 22.4 Append `:delegation` trajectory entry to the caller's session.
- [x] 22.5 Add `test/ash_harness/delegation_test.exs` covering: permitted delegation succeeds, unpermitted returns `:delegation_not_permitted`, depth cap exceeded returns `:delegation_depth_exceeded`, delegate uses its own actor, delegate's mutations don't count against caller's budget, reply is a string only.

## 23. Telemetry (Phase 5)

- [x] 23.1 Implement `AshHarness.Telemetry.emit/3` wrapper respecting `config :ash_harness, :telemetry, enabled: true|false`.
- [x] 23.2 Wire the gate-pipeline events from the telemetry-events spec into each gate (`scope.violation`, `reasoning.missing`, `confirmation.requested|approved|rejected`, `budget.exceeded`, `policy.denied`).
- [x] 23.3 Wire `[:ash_harness, :action, :executed]` in the executor with `duration_ms` and status.
- [x] 23.4 Wire `[:ash_harness, :context, :rendered]` on cache miss and the renderer call.
- [x] 23.5 Wire `[:ash_harness, :delegation, :*]` events.
- [x] 23.6 Implement OTel span attribute attachment (`ash_harness.*`) using the active span; no-op when no active span.
- [x] 23.7 Add `test/ash_harness/telemetry_test.exs` attaching handlers and asserting events fire with expected metadata; assert `enabled: false` suppresses all events.

## 24. Eval framework (Phase 6)

- [x] 24.1 Define `AshHarness.Eval.Scenario`, `AshHarness.Eval.Gate`, `AshHarness.Eval.Report`, `AshHarness.Eval.Result` structs (no `composite_score` field).
- [x] 24.2 Implement `AshHarness.Eval` `use` macro and `scenario/2`, `agent/1`, `setup/1`, `prompt/1`, `gate/2`, `report/2` macros.
- [x] 24.3 Implement `gate :resource_state` body parsing into `assert :record_name, :field, predicate_fn` form; fail-fast at scenario level on any failure.
- [x] 24.4 Implement `gate :invariant` for arbitrary truthy-returning code blocks.
- [x] 24.5 Implement `report :trajectory` checks: `max_actions`, `max_tokens`, `includes_sequence` (ordered subsequence), `excludes`.
- [x] 24.6 Implement `report :qualitative` with `criterion :name, threshold:, prompt:` calling the configured judge model via Jido (no separate transport).
- [x] 24.7 Implement `AshHarness.Eval.Runner.run/2` and `run_all/2` per the eval-framework spec; auto-confirm default `:always_approve`; alternatives `:always_reject` and `:custom`.
- [x] 24.8 Implement scenario isolation: ETS sandbox per scenario for ETS resources; transaction wrap for AshPostgres resources.
- [x] 24.9 Add `mix ash_harness.eval` Mix task running all eval modules in `test/evals/` (or configurable).
- [x] 24.10 Add `test/ash_harness/eval/runner_test.exs` covering: gate pass, gate fail, passing gate + failing diagnostic (still passes), no `composite_score` field, isolation between scenarios, auto-confirm behavior.

## 25. Examples + docs (Phase 8)

- [x] 25.1 Create `examples/triage/` minimal agent on test resources with a runnable `mix run` script.
- [x] 25.2 Create `examples/postgres/` mirroring the triage example backed by AshPostgres (gated by `MIX_ENV=postgres`).
- [x] 25.3 Create `examples/multi_agent/` showing supervisor + delegate.
- [x] 25.4 Move `design/architecture/coming-from-langgraph-swarm.md` content into a top-level `docs/coming-from-langgraph-swarm.md` (or symlink) and link from the README.
- [x] 25.5 Author `docs/coexistence-with-ash-ai.md` describing how to use both libraries together.
- [x] 25.6 Replace `README.md` with a real quickstart (≤5 minute path: install, declare a resource, declare an agent, run).
- [x] 25.7 Add `CHANGELOG.md` for v0.1.0 listing every spec in `What Changes`.
- [x] 25.8 Configure `ex_doc` (`mix.exs` `:docs`); ensure module-doc completeness for all public-API modules.

## 26. CI + lint (Phase 8)

- [x] 26.1 Add `.github/workflows/ci.yml` with a matrix: default test, `MIX_ENV=postgres mix test` (Docker compose for Postgres), `MIX_ENV=integration mix test` (nightly schedule, requires API key from secrets).
- [x] 26.2 Add `mix format --check-formatted` to CI.
- [x] 26.3 Configure `credo --strict`; add `.credo.exs`.
- [x] 26.4 Configure `dialyzer`; add `.dialyzer_ignore.exs` only with explicit comments.
- [x] 26.5 Verify all integration tests are tagged `@tag :integration` and excluded by default.

## 27. τ-bench airline port (Phase 7)

- [x] 27.1 Scaffold `benchmarks/tau_bench_airline/` as a child mix package depending on `:ash_harness` from the parent path.
- [x] 27.2 Implement `TauBenchAirline.Domain` with `AshHarness.Domain` extension and seeded vocabulary.
- [x] 27.3 Implement `TauBenchAirline.Customer` resource with attributes from current τ-bench schema and `agent_annotations`.
- [x] 27.4 Implement `TauBenchAirline.Reservation` resource with `:change_flight` and `:cancel` actions, fare-class policy validations, and per-customer policy.
- [x] 27.5 Implement `TauBenchAirline.Flight` resource with `:search` action.
- [x] 27.6 Author `TauBenchAirline.Agent` (full scope, `confirm_before` and `require_reasoning_for` for `:change_flight` and `:cancel`, constraints aligned with τ-bench expectations).
- [x] 27.7 Author `TauBenchAirline.UserSimulator` agent with empty scope.
- [x] 27.8 Implement seeders that hydrate ETS resources from `data/customers.json`, `data/reservations.json`, `data/flights.json`.
- [x] 27.9 Author at least 10 scenarios mapping τ-bench tasks to `AshHarness.Eval.Scenario` form with gates and reports.
- [x] 27.10 Implement the multi-turn runner extension (agent ↔ user simulator loop with `max_turns` default 12 and goal-met detection).
- [x] 27.11 Add `mix tau_bench.run` task that executes all scenarios and prints gate-pass-rate aggregate + per-scenario summary.
- [x] 27.12 Author `benchmarks/tau_bench_airline/README.md` with the methodology, model used, results, and reproduction commands.
- [x] 27.13 Document any divergence from upstream τ-bench scoring methodology.

## 28. Acceptance + release prep (Phase 8)

- [x] 28.1 Run `mix compile --warnings-as-errors` clean.
- [x] 28.2 Run `mix test` clean.
- [x] 28.3 Run `mix credo --strict` clean.
- [x] 28.4 Run `mix dialyzer` clean.
- [x] 28.5 Run `mix tau_bench.run` against the headline model and capture results in the τ-bench README.
- [x] 28.6 Resolve open questions #1 (`ash_ai`), #2 (`jido_composer` API), #3 (τ-bench shape) — update ADRs and design folder if anything changed.
- [x] 28.7 Tag `v0.1.0`; publish to hex (do not push from CI; manual step).
