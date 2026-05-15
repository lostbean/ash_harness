## 1. Setup

- [x] 1.1 Bump `mix.exs` version to `0.1.2`
- [x] 1.2 Add `{:splode, "~> 0.2"}` to `mix.exs` deps; run `mix deps.get`

## 2. Errors module tree (TDD-first; landing before gate changes)

- [x] 2.1 Write `test/ash_harness/errors_test.exs` asserting that each of the seven structs (`ScopeViolation`, `PolicyDenied`, `ValidationFailed`, `MutationLimitExceeded`, `ReasoningRequired`, `DelegationNotPermitted`, `DelegationDepthExceeded`) can be constructed, exposes the documented fields, implements `Exception.message/1`, and classifies under `AshHarness.Errors.classify/1` to the right Splode class atom — run, see failures
- [x] 2.2 Implement `lib/ash_harness/errors/scope_violation.ex`, `policy_denied.ex`, `validation_failed.ex`, `mutation_limit_exceeded.ex`, `reasoning_required.ex`, `delegation_not_permitted.ex`, `delegation_depth_exceeded.ex` as `defexception` modules with the design.md schema. `DelegationDepthExceeded` fields: `from, to, depth, max_depth`.
- [x] 2.3 Implement `AshHarness.Errors.classify/1` dispatching on struct type; run errors_test, see green
- [x] 2.4 Add Splode class registration / setup if needed (audit Splode docs first; if it's only needed as a base for `defexception` no extra wiring required)

## 3. request_id threading (TDD-first; prereq for telemetry metadata)

- [x] 3.1 Write `test/ash_harness/harness/request_id_test.exs` asserting that (a) two consecutive dispatches on the same session emit `[:ash_harness, :action, :executed]` events with distinct `:request_id` values, (b) a single dispatch that fails the scope gate emits `:scope, :violation` AND `:scope, :checked` sharing one `:request_id`, (c) the OTel `ash_harness.request.id` attribute on the dispatch span equals that `:request_id` — run, see failures
- [x] 3.2 In `lib/ash_harness/harness/generated_action.ex` `dispatch/5`, generate `request_id = Ecto.UUID.generate()` (or `:uuid.uuid4()` if Ecto isn't a dep — verify) at entry; thread it as a local
- [x] 3.3 Replace the `set_dispatch_otel_attrs` call to include `request_id` (already wired to set `request.id` — confirm it now sources from the local, not the intent)
- [x] 3.4 Update every `Telemetry.emit/4` / `:telemetry.execute/3` call inside `generated_action.ex` to merge `request_id: request_id` into metadata
- [x] 3.5 Update gate modules (`scope_gate.ex`, `reasoning_gate.ex`, `confirmation_gate.ex`, `budget_gate.ex`, `policy_gate.ex`) so they accept the `request_id` as an argument and include it in their emitted events
- [x] 3.6 Run `request_id_test`, see green; also run the full telemetry suite

## 4. Fix repair:feedback attempt count

- [x] 4.1 Write a failing test in `test/ash_harness/harness/repair_test.exs` (or new file) asserting that when an action fails validation for the third time in a turn, `[:ash_harness, :repair, :feedback]` fires with `attempt: 3` (not `1`) — run, see failure
- [x] 4.2 At `lib/ash_harness/harness/generated_action.ex:314`, replace the hardcoded `%{attempt: 1}` with `%{attempt: attempts}` (the variable already in scope at line 61) — propagate the local into the emit call site
- [x] 4.3 Rename `repair:exhausted`'s measurement key from `attempts` to `total_attempts` at line 203; update the matching test
- [x] 4.4 Run repair tests + telemetry tests, see green

## 5. Gate :checked pass-events

- [x] 5.1 Write a failing test asserting that on a clean successful dispatch all four `:checked` events fire once each with the same `:request_id`, and that on a policy-refused dispatch `:scope, :checked`, `:reasoning, :checked`, `:budget, :checked`, AND `:policy, :checked` (with `passed: false`) all fire alongside the existing `:policy, :denied` event — run, see failures
- [x] 5.2 Emit `[:ash_harness, :scope, :checked]` at the end of `scope_gate.ex check/3` regardless of pass/fail; metadata: `%{agent, resource, action, passed, request_id}`
- [x] 5.3 Emit `[:ash_harness, :reasoning, :checked]` at the end of `reasoning_gate.ex check/3`; measurements `%{required, present}`; metadata as above
- [x] 5.4 Emit `[:ash_harness, :budget, :checked]` at the end of `budget_gate.ex check/3`; measurements `%{count, max}`; metadata as above
- [x] 5.5 Emit `[:ash_harness, :policy, :checked]` at the end of `policy_gate.ex check/3`; metadata with `passed: boolean`
- [x] 5.6 Run pass-events test, see green

## 6. Gate returns: convert to struct errors

- [x] 6.1 Update the existing gate tests in `test/ash_harness/harness/gates_test.exs` to assert struct-error returns instead of atom tuples; run, see failures (this is TDD-first for the breaking change)
- [x] 6.2 In `scope_gate.ex`, return `{:error, %AshHarness.Errors.ScopeViolation{...}}` on refusal
- [x] 6.3 In `reasoning_gate.ex`, return `{:error, %AshHarness.Errors.ReasoningRequired{...}}` on refusal
- [x] 6.4 In `budget_gate.ex`, return `{:error, %AshHarness.Errors.MutationLimitExceeded{...}}` on refusal
- [x] 6.5 In `policy_gate.ex`, return `{:error, %AshHarness.Errors.PolicyDenied{ash_error: e, ...}}` on refusal; populate `ash_error_class` field for telemetry
- [x] 6.6 In `delegation.ex`, return `{:error, %AshHarness.Errors.DelegationNotPermitted{...}}` for not-permitted AND `{:error, %AshHarness.Errors.DelegationDepthExceeded{from, to, depth, max_depth}}` for depth exceeded. Both become structs.
- [x] 6.7 Update `lib/ash_harness/harness/repair.ex` pattern matches in `format_feedback/2` and `retryable?/1` to match on the new structs
- [x] 6.8 Search `lib/` and `test/` for any remaining `{:error, :scope_violation` / `:policy_denied` / `:budget_exceeded` / `:reasoning_required` / `:validation_failed` / `:delegation_not_permitted` patterns and update
- [x] 6.9 Run full `mix test`, see green

## 7. Telemetry metadata drift fixes (existing events)

- [x] 7.1 Write `test/ash_harness/telemetry_metadata_test.exs` asserting each of the ten events' metadata shape per the spec (confirmation:approved has `respondent`, `duration_ms`; confirmation:rejected has `respondent`; policy:denied has `ash_error_class`; action:executed has `records_returned` for reads / `records_changed` for mutations / `error_class`; delegation:started+ended have `depth`, `target_trajectory_id`, `request_id`; eval:scenario:stop has `agent`, `gates_passed`, `gates_failed`; eval:gate:checked has `scenario`, `passed`; eval:report:computed has `scenario`, `kind`, `observations`) — run, see failures
- [x] 7.2 Update `confirmation_gate.ex` and `harness.ex` `resume/2` paths to thread `respondent` (sourced from `ApprovalResponse{respondent: _}`; default `:unspecified`) and `duration_ms` (computed from `ApprovalRequest{requested_at: _}`) into the `:approved` / `:rejected` events; add a `respondent` field to `ApprovalResponse` if absent and wire `:auto_confirm` to set `:auto_confirm`
- [x] 7.3 Update `policy_gate.ex` to compute `ash_error_class` from the Ash error and include it in `:denied` metadata
- [x] 7.4 Update `generated_action.ex` `action:executed` emission to include `records_returned` (for `:read`, the count of records returned), `records_changed` (for mutations, `1` on success), and `error_class` (from struct error class, `nil` on success)
- [x] 7.5 Update `lib/ash_harness/delegation.ex` (or the new initiate.ex) to include `depth`, `target_trajectory_id`, `request_id` in `:started` and `:ended` metadata
- [x] 7.6 Update `lib/ash_harness/eval/runner.ex` `:scenario, :stop` to include `agent`, `gates_passed`, `gates_failed`; `:gate, :checked` to include `scenario`, `passed`; `:report, :computed` to include `scenario`, `observations`
- [x] 7.7 Run telemetry_metadata_test, see green; run full telemetry suite

## 8. TrajectoryEntry.data field

- [x] 8.1 Write a failing test in `test/ash_harness/harness/trajectory_entry_test.exs` asserting that `%TrajectoryEntry{}` has a `data` field defaulting to `%{}`, and that a delegation entry populates `data.reply_text` and `data.target_trajectory_id` — run, see failure
- [x] 8.2 Add `data: %{}` to `lib/ash_harness/harness/trajectory_entry.ex` struct
- [x] 8.3 Run trajectory_entry_test (the struct shape test), see green for the struct piece (the delegation piece stays red until step 9)

## 8b. Delegate `as:` alias DSL (TDD-first; prereq for the skill)

- [x] 8b.1 Write `test/ash_harness/agent_test.exs` additions asserting: (a) `delegate MyApp.Foo, as: "foo", for: "..."` parses and `Agent.Info.delegates/1` exposes `:as` as a binary; (b) a `delegate` without `as:` raises a compile-time verifier error; (c) two delegates with the same alias (case-insensitive) raise a compile-time verifier error — run, see failures
- [x] 8b.2 Add `as: [type: :string, required: true]` schema entry to the `delegate` entity in `lib/ash_harness/agent/dsl.ex`. Reorder `args:` to `[:agent_module]` and require `as:` and `for:` via the options
- [x] 8b.3 Add `as: nil` to `%DelegateEntry{}` in `lib/ash_harness/agent/delegation/delegate_entry.ex` and update its typespec
- [x] 8b.4 Add verifier `lib/ash_harness/agent/verifiers/delegate_aliases_unique.ex` rejecting duplicate aliases (case-insensitive)
- [x] 8b.5 Wire the new verifier in `dsl.ex` `verifiers:` list
- [x] 8b.6 Update fixture agents under `test/support/` that declare delegates to add `as:` aliases (search `delegates_to do` blocks)
- [x] 8b.7 Run full test suite; see green
- [x] 8b.8 NOTE: this is technically a breaking DSL change for v0.1.2 — call out in CHANGELOG entry (task 10.3)

## 9. Delegation refactor + skill (TDD-first integration test)

- [x] 9.1 Write `test/ash_harness/delegation/skill_test.exs` asserting: (a) the orchestrator for an agent with non-empty `delegates_to` contains the `AshHarness.Delegation.Skill` node and it is NOT gated by `requires_approval`; (b) the orchestrator for an agent with no `delegates_to` does NOT contain that node; (c) invoking the skill with a target alias (e.g. `"billing"`) dispatches through `AshHarness.Delegation.initiate/4` and returns the delegate's reply string; (d) invoking with an unknown alias returns an error tool result listing the agent's declared aliases; (e) the caller's trajectory after a successful delegation has one entry with `data.reply_text` and `data.target_trajectory_id`; (f) if the child halts requesting confirmation, the skill returns `{:error, "delegate halted: requires confirmation"}` (nested-HITL deferral, design.md open question) — run, see failures
- [x] 9.2 Refactor: move the current `Delegation.initiate/4` body into `lib/ash_harness/delegation/initiate.ex` as `AshHarness.Delegation.Initiate.run/4`; keep `lib/ash_harness/delegation.ex` as a thin re-export delegating to it
- [x] 9.3 Add `lib/ash_harness/delegation/result.ex` with a small `%Result{reply_text, target_trajectory_id, target_trajectory, status}` struct used internally
- [x] 9.4 Generate `target_trajectory_id` in `Initiate.run/4` at start (UUID v4)
- [x] 9.5 Update `Initiate.run/4` so the appended caller trajectory entry includes `data: %{reply_text: ..., target_trajectory_id: ...}`
- [x] 9.6 Update telemetry emission in `Initiate.run/4` so `:started` and `:ended` include `target_trajectory_id` and `request_id` (request_id is sourced from the calling dispatch's local — thread it through)
- [x] 9.7 Create `lib/ash_harness/delegation/skill.ex`: a `Jido.Action` taking `(target: string, question: string)`. Resolve `target` against the agent's `delegates_to` `:as` aliases (case-insensitive exact match on the alias string). On match → call `AshHarness.Delegation.initiate/4`. On no match → return `{:error, "Unknown delegate target '#{target}'. Available aliases: #{list}"}`. On child-halt (the child agent suspended with an ApprovalRequest) → return `{:error, "delegate halted: requires confirmation"}` per nested-HITL deferral.
- [x] 9.8 Update `lib/ash_harness/harness/orchestrator_factory.ex` `build/1` to conditionally append the `AshHarness.Delegation.Skill` node when the agent's `delegates_to` is non-empty
- [x] 9.9 Update `lib/ash_harness/tool_gen/orchestrator_module.ex` `tool_nodes/0` generation to include the skill node entry without `requires_approval`
- [x] 9.10 Run delegation tests, see green; run trajectory_entry_test green; run full delegation suite

## 10. CLAUDE.md + README + CHANGELOG refresh

- [x] 10.1 Rewrite the "Project state" section in `CLAUDE.md` to reflect v0.1.1+ reality (phases 1–6 complete, ~80 modules, design docs are reference not future spec); keep architecture pointers and house rules
- [x] 10.2 Update `README.md` line 164 (or wherever "v0.1.0 is the first release" appears) to say v0.1.1 is shipped and v0.1.2 is the audit-followup
- [x] 10.3 Add a v0.1.2 entry to `CHANGELOG.md` documenting: structured error returns from gates (breaking for direct gate callers), `:request_id` in all telemetry metadata, four new `:checked` pass-events, delegation tool now usable from LLM, `repair:feedback` reports real attempt count, `repair:exhausted` `attempts` → `total_attempts`

## 11. Design doc updates (code-as-truth)

- [x] 11.1 Update `design/implementation/public-api.md`: `AshHarness.Tool.dynamic/2` returns `AshHarness.Tool.t()`, takes `(keyword(), keyword())`; remove `ContextRenderer.resource_summary/2` from the list; document `ContextRenderer.render_resource/3` as taking `(module, module, actor)` not `opts`
- [x] 11.2 Update `design/adrs/0005-tool-generation-hybrid.md` to match the `dynamic/2` signature
- [x] 11.3 Update `design/layers/05-context-renderer.md` to match `render_resource/3` actor arg; note `RenderedContext` struct collapsed to `:initial_text + :token_estimate + :resource_details + :warnings`
- [x] 11.4 Update `design/layers/09-delegation.md` to describe the new skill wiring + trajectory `data` field
- [x] 11.5 Update `design/layers/11-telemetry.md` to add the four `:checked` events and the `:request_id` correlation field
- [x] 11.6 Update `design/architecture/module-tree.md` to: (a) document `errors/` as populated, (b) note `repair.ex` lives under `harness/`, (c) note `delegation/` now contains `initiate.ex` + `result.ex` + `skill.ex`, (d) note `confirmation_gate.ex` naming, (e) note `context_renderer` sections are inlined as private functions, (f) note `eval/gate.ex` + `eval/report.ex` consolidate the per-kind files

## 12. Open questions: close the resolved set

- [x] 12.1 In `design/implementation/open-questions.md`, mark Q#2 (Jido Composer API surface) resolved by v0.1.1 with reference to `harness.ex:100-132`
- [x] 12.2 Mark Q#4 (Spark v2.x compatibility) resolved
- [x] 12.3 Mark Q#5 (Session propagation to Jido.Action.run/2) resolved via `ctx[:ash_harness_session_pid]`
- [x] 12.4 Mark Q#7 (Ash.can? :maybe return) resolved
- [x] 12.5 Mark Q#11 (Confirmation flow round-trip) resolved via the v0.1.1 SessionAgent + suspension work
- [x] 12.6 Mark Q#14 (OTel span attachment) resolved
- [x] 12.7 Re-audit Q#3 (τ-bench schema), Q#6 (token estimator), Q#8 (short-name conflict suggestion), Q#9 (generic action normalization), Q#10 (read filter parameters), Q#12 (mutation count across run/resume), Q#13 (hot reload), Q#16 (eval transactional isolation), Q#17 (judge cost caching) — for each, read the code, decide resolved/still-open, write a one-line resolution or "still open: …" note in `open-questions.md`

## 13. Verify and validate

- [x] 13.1 Run `mix format --check-formatted`; fix any formatting
- [x] 13.2 Run `mix test`; full suite must be green (301/301)
- [x] 13.3 Run `mix credo --strict`; fix or document any new findings (refactored Enum.map_join + cond→if; disabled ExceptionNames heuristic)
- [x] 13.4 Run `mix dialyzer`; fix any new warnings introduced by the change (refreshed `.dialyzer_ignore.exs` line numbers)
- [x] 13.5 Run `npx openspec validate audit-followup-v0-1-2 --strict`; must report valid
