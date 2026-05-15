# Proposal — Audit Follow-up (v0.1.2)

## Why

A deep design-vs-implementation audit (run on 2026-05-15 against v0.1.1)
surfaced ten gaps where the code drifted from the documented design or
where the design didn't yet reflect implementation reality. The library
is functionally ~90% conformant, but three of the gaps are real holes
worth closing before further feature work, and several others are
documentation debt that misleads future contributors.

The largest hole: **the delegation tool is half-wired**.
`AshHarness.Delegation.initiate/4` is implemented end-to-end and the
context renderer advertises `delegate(target, question)` in the LLM's
meta-tools section, but no `Jido.Action` is generated and added to the
orchestrator's node list — so the LLM sees the hint in its prompt but
has no tool to call. The other items range from a one-line telemetry
bug (`repair:feedback` hardcodes `attempt: 1`) to documentation drift
that actively misleads (`CLAUDE.md` claims `lib/` is a "design-stage
scaffold" containing only `AshHarness.hello/0` — neither is true at
v0.1.1).

v0.1.2 closes the ten audit items. No new feature surface; all changes
are corrections.

## What Changes

- Wire the delegation meta-tool. Add a single dynamic
  `Jido.Action` under `lib/ash_harness/delegation/skill.ex` that takes
  `(target, question)`, runs through `Delegation.initiate/4`, and is
  added to the orchestrator's node list whenever `delegates_to` is
  non-empty. The action returns only text per ADR 0004.
- Refactor `lib/ash_harness/delegation.ex` into `delegation/initiate.ex`
  + `delegation/result.ex` + `delegation/skill.ex`, matching the
  module-tree the design specifies. Public function
  `AshHarness.Delegation.initiate/4` keeps its current arity and return
  shape.
- Add a `data` field to `%TrajectoryEntry{}` shaped
  `%{reply_text: binary, target_trajectory_id: binary}` for delegation
  entries, per design layer 09 lines 134–141. Populate it from the
  delegation skill so observability tools can fetch the delegate's
  full trace.
- Generate a per-dispatch `request_id` (UUID) at `GeneratedAction.dispatch/5`
  entry. Thread it through OTel attrs (already set as `request.id`) and
  into every telemetry event emitted by that dispatch. Prereq for the
  metadata fixes below.
- Fix the hardcoded `attempt: 1` at
  `lib/ash_harness/harness/generated_action.ex:314`. Emit the real
  per-(resource, action) attempt count from the local already in scope
  at line 61.
- Close telemetry metadata drift across ten events: add the missing
  fields (`respondent`, `duration_ms`, `ash_error_class`,
  `records_returned`/`records_changed`, `error_class`, `depth`,
  `request_id`, `agent`, `gates_passed`/`gates_failed`, `scenario`,
  `passed`, `observations`) to the events that already exist. Rename
  `repair:exhausted`'s `attempts` measurement to `total_attempts` per
  the spec.
- Add four `:checked` pass-events (`scope:checked`, `reasoning:checked`,
  `budget:checked`, `policy:checked`) emitted on every successful gate
  pass. OTel attrs already carry `*.passed=true` on the dispatch span;
  the events let listeners count pass rates without span sampling.
- Build the errors module tree. Create six structured error types
  under `lib/ash_harness/errors/` using `Splode`:
  `ScopeViolation`, `PolicyDenied`, `ValidationFailed`,
  `MutationLimitExceeded`, `ReasoningRequired`,
  `DelegationNotPermitted`. **BREAKING** for gates: gate return shape
  changes from `{:error, atom()}` to `{:error, struct()}`.
  `Repair.format_feedback/2` pattern-matches on the structs.
- Update design docs to reflect code-as-truth decisions:
  - `public-api.md` + `ADR 0005`: `Tool.dynamic/2` returns
    `AshHarness.Tool.t()` (not `Jido.Action.t()`) and takes
    `(keyword(), keyword())`.
  - layer 05: `render_resource/3` takes `actor` (not `opts`); document
    that `resource_summary/2` is removed from the public API.
  - `module-tree.md`: document the consolidations (single `repair.ex`
    nested under `harness/`, inlined `context_renderer` sections,
    single `gate.ex`/`report.ex` under `eval/`, `confirmation_gate.ex`
    naming, `errors/` directory now populated).
- Close resolved open questions in `design/implementation/open-questions.md`:
  Q#2, Q#4, Q#5, Q#7, Q#11, Q#14 with a resolution note. Re-audit
  Q#3, Q#6, Q#8, Q#9, Q#10, Q#12, Q#13, Q#16, Q#17 and close any that
  v0.1.1/v0.1.2 settles.
- Refresh `CLAUDE.md` "Project state" section to reflect v0.1.1
  reality (phases 1–6 complete, ~80 modules, design docs are
  reference not future spec). Update `README.md` to say v0.1.1 is the
  current stable release (line 164).

## Capabilities

### Modified Capabilities

- `delegation`: delegation is now invocable from the LLM. A single
  dynamic `delegate(target, question)` skill is added to the
  orchestrator whenever the agent has non-empty `delegates_to`. The
  skill enforces the ADR 0004 text-only contract and writes a
  delegation trajectory entry with a `data` payload pointing at the
  child trajectory.
- `harness-runtime`: every dispatch has a `request_id`. All five gates
  return structured `%AshHarness.Errors.*{}` errors instead of atom
  reasons (**BREAKING** for callers pattern-matching gate returns;
  the public `AshHarness.Harness.run/3` return signature is
  unchanged).
- `telemetry-events`: ten events gain missing metadata fields per the
  layer 11 spec; four new `:checked` pass-events fire on every gate
  pass; `repair:feedback` reports the real attempt count;
  `repair:exhausted` renames `attempts` → `total_attempts`.
- `repair-loop`: feedback formatter pattern-matches on the new error
  structs; behavior unchanged from a caller's perspective.

### Added Capabilities

None — this change closes gaps in existing capabilities rather than
introducing new ones.

## Impact

- **Code**: new `lib/ash_harness/delegation/{initiate,result,skill}.ex`
  replacing `lib/ash_harness/delegation.ex`; new
  `lib/ash_harness/errors/` with six struct modules; edits to all five
  gates under `lib/ash_harness/harness/`; edits to
  `generated_action.ex` (request_id, attempt count fix, telemetry
  metadata); edits to `delegation` orchestrator wiring in
  `orchestrator_factory.ex` + `tool_gen/orchestrator_module.ex`;
  TrajectoryEntry struct gains a `data` field; possibly new gate
  emitters for `:checked` events under each `*_gate.ex`.
- **Mix package**: adds `{:splode, "~> 0.2"}` for error structs.
  No optional / dev-only additions.
- **Public API**: `AshHarness.Delegation.initiate/4` keeps current
  arity and return shape. `AshHarness.Tool.dynamic/2` documented to
  return `AshHarness.Tool.t()`. `ContextRenderer.render_resource/3`
  documented to take `actor`. Gate return shape is internal but
  pattern-matches in user-written eval gates against
  `%AshHarness.Errors.*{}` are now supported (and atom matches break).
- **Telemetry**: ten events gain new metadata keys; four new event
  names start firing on every gate pass. Existing listeners keep
  working but should pick up the new keys.
- **Design docs**: `public-api.md`, `ADR 0005`, `module-tree.md`,
  `layer 05`, `layer 09`, `layer 11` updated. Six open questions
  closed with resolution notes.
- **Out of v0.1.2**: validators.ex JSON-Schema sanity checks
  (layer 06 gap, deferred to v0.2); `render_resource/3` opts keyword
  signature (design updated to match code; opts form deferred);
  reachability `build/1` runtime-vs-DSL-state API drift (deferred);
  embedded resource recursion in `AshTypeMapper` (open question Q#9
  re-audit may settle).
