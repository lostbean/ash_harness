# Design — Audit Follow-up (v0.1.2)

## Context

A design-vs-implementation audit run on 2026-05-15 against v0.1.1
surfaced ten gaps. They fall into three groups:

1. **Real functional holes** — delegation tool not wired to the
   orchestrator; `repair:feedback` event hardcodes `attempt: 1`;
   no `request_id` correlates events within a single dispatch.
2. **Telemetry drift** — ten existing events have missing metadata
   fields (`respondent`, `request_id`, `error_class`,
   `records_changed`, etc.); four `:checked` pass-events specified by
   layer 11 don't fire.
3. **Documentation debt** — `CLAUDE.md` claims `lib/` is a "design-
   stage scaffold"; design specifies an `errors/` module tree that
   doesn't exist; several public-api signatures diverge from code.

This change closes all ten. No new feature surface, just corrections.

The largest decision is whether to convert gate returns from atom
tuples to struct errors. We decided to do it (Decision 4 below) — the
churn is real but it's a one-time price that lets every downstream
piece (Repair formatter, telemetry metadata, eval gates) work from
typed data rather than atom dispatch.

## Goals / Non-Goals

**Goals:**

- LLM can actually invoke `delegate(target, question)` and the
  delegation skill enforces ADR 0004 (text-only, isolated scope).
- Every telemetry event carries the metadata the design specifies,
  including a `request_id` that correlates events within a dispatch.
- Gate refusals return structured `%AshHarness.Errors.*{}` errors so
  the repair formatter, telemetry encoder, and host code can pattern-
  match on types instead of atoms.
- Design docs are code-as-truth where the implementation has settled
  (Tool.dynamic/2, render_resource/3, module-tree consolidations).
- `CLAUDE.md` and `README.md` describe v0.1.1+ reality accurately.

**Non-Goals:**

- Implementing `lib/ash_harness/schema/validators.ex` (JSON Schema
  sanity checks — layer 06 gap, deferred to v0.2).
- Adding the design's `(module, module, keyword())` form of
  `render_resource/3` (we update the design to match the `actor` arg
  the code uses; opts form deferred).
- Changing `Reachability.build/1` to accept a runtime agent module
  (still takes DSL state at compile time).
- Adding embedded-resource recursion in `AshTypeMapper` (open
  question Q#9 re-audit handles this separately).
- New features. Every change is a correction or a closure of a known
  gap.

## Decisions

### 1. Delegation tool: single dynamic skill, not per-target

**Decision:** One `AshHarness.Delegation.Skill` Jido.Action takes
`(target: string, question: string)`. `OrchestratorFactory.build/1`
adds it to the node list only when the agent's `delegates_to` is
non-empty.

**Alternatives considered:**

- One generated tool per delegate target (e.g.
  `delegate_to_billing_agent`). Rejected — heavier compile-time
  machinery for marginal LLM benefit; the prompt already lists
  acceptable targets via the existing meta-tools section.
- Skip the tool, only fix the prompt. Rejected — the design specifies
  the tool and the user wants delegation usable from the LLM.

**Why this works:** Mirrors the existing `LoadResourceSkill` pattern
exactly, so wiring is well-understood. Case-insensitive target
matching is done in the skill (same as `LoadResourceSkill` does for
resource names). Returns an error tool result if the target doesn't
match any declared delegate.

### 2. Module layout: split delegation.ex into a subdir

**Decision:** Refactor `lib/ash_harness/delegation.ex` into:

- `lib/ash_harness/delegation/initiate.ex` — current monolithic
  function moves here, renamed `Initiate.run/4`. Public
  `AshHarness.Delegation.initiate/4` becomes a thin re-export.
- `lib/ash_harness/delegation/result.ex` — a small struct used
  internally so telemetry and trajectory share a shape (currently
  values are constructed ad-hoc).
- `lib/ash_harness/delegation/skill.ex` — the new Jido.Action.

**Alternatives considered:**

- Keep `delegation.ex` monolithic. Rejected — the design explicitly
  specifies the subdir, and the file is already at the size where
  splitting helps testability.

### 3. TrajectoryEntry.data field

**Decision:** Add `data: %{}` to `%TrajectoryEntry{}` (default
empty). For delegation entries, populate with
`%{reply_text, target_trajectory_id}`. Existing trajectory entries
keep `data: %{}`.

**Alternatives considered:**

- Stash on the existing `metadata` field. Rejected — `metadata` is
  used by the telemetry encoder for OTel attributes, and mixing
  payload data into it muddles the contract. A separate `data` is
  what the design specifies.

### 4. Gate returns become struct errors (BREAKING)

**Decision:** All five gates return
`{:error, %AshHarness.Errors.*{}}` instead of `{:error, atom()}`.
Six error structs are created under `lib/ash_harness/errors/`:

| Struct | Fields | Splode class |
|---|---|---|
| `ScopeViolation` | `agent, resource, action` | `:scope` |
| `PolicyDenied` | `agent, resource, action, actor, ash_error` | `:policy` |
| `ValidationFailed` | `agent, resource, action, ash_error` | `:validation` |
| `MutationLimitExceeded` | `agent, count, max` | `:budget` |
| `ReasoningRequired` | `agent, resource, action` | `:reasoning` |
| `DelegationNotPermitted` | `from, to, reason` | `:delegation` |

`Repair.format_feedback/2` and `retryable?/1` pattern-match on these
structs instead of atom tuples.

**Alternatives considered:**

- Add structs but keep atom-return contracts. Rejected — duplicate
  source of truth invites drift. The whole point is to get rid of
  atom dispatch.
- Skip and update the design to remove `errors/`. Rejected — the
  audit specifically asks us to build them; structured errors let
  telemetry encode `ash_error_class` properly and let host code
  pattern-match.

**Migration plan:** This is a v0.1.x breaking change for callers
that pattern-match on `{:error, :scope_violation, ...}` shaped
returns from gates. The public `Harness.run/3` return shape doesn't
change (it's already `{:ok, _, _}` | `{:halt, _, _}` | `{:error, _, _}`).
The breakage is for code that calls a gate's `check/1`/`check/2`
directly — likely no one outside this repo. We document in
`CHANGELOG.md`.

### 5. request_id: per-dispatch UUID, generated in GeneratedAction

**Decision:** `GeneratedAction.dispatch/5` generates a fresh
`UUID.uuid4()` binary at entry, stores it in a local, sets it as the
`ash_harness.request.id` OTel attribute (already wired), and threads
it through every `Telemetry.emit/4` call within that dispatch via
metadata `:request_id`.

**Alternatives considered:**

- Per-turn id at `Harness.run/3`. Rejected — turn-level granularity
  is too coarse; one turn fires N tool dispatches. We want one id
  per dispatch so listeners can group "all events for one tool call."
- Both turn id and dispatch id. Rejected — yagni; adds Session field
  for marginal benefit. Session id + request_id is enough.

### 6. `:checked` pass-events: emit always, regardless of pass/fail

**Decision:** Each gate emits its `:checked` event on every
evaluation, whether the gate passes or refuses. Metadata includes
`passed: boolean` (where applicable). The `:violation` / `:exceeded`
/ `:denied` failure-class events still fire on failure as before.

**Alternatives considered:**

- Behind a config flag. Rejected — the user accepted full design
  alignment and OTel attrs are already always-on; consistency wins.
- Only emit on failure. Rejected — the design specifies them and
  listeners want pass-rate metrics.

**Volume:** Four extra events per dispatch (scope, reasoning,
budget, policy `:checked`). For a typical 5-tool turn that's 20
extra events per turn. `:telemetry.execute` is cheap when no
handlers are attached; with handlers, the marginal cost is the
handler's body. We accept this.

### 7. Public-api code-as-truth

**Decision:** Update design docs to match the implementation for
two signatures:

- `AshHarness.Tool.dynamic/2` returns `AshHarness.Tool.t()` (a
  wrapper struct), not `Jido.Action.t()`. Takes
  `(keyword(), keyword())`, not `(String.t(), keyword())`.
  Update ADR 0005 and `public-api.md`.
- `AshHarness.ContextRenderer.render_resource/3` takes
  `(agent, resource, actor)` — design's `opts` form is deferred to
  v0.2. Remove `resource_summary/2` from `public-api.md` (it was
  never implemented).

**Alternatives considered:**

- Change code to match design. Rejected — the struct wrapper carries
  dispatch context and is what tests expect; reversing it costs more
  than reversing the design.

### 8. CLAUDE.md rewrite

**Decision:** Replace the "Project state" section with a one-
paragraph description of v0.1.1 reality and a quick-jump table to
the most-relevant code locations. Keep the architecture pointers and
the house rules — those are still accurate.

## Risks / Trade-offs

- **Risk:** Gate return shape change breaks downstream pattern
  matches. **Mitigation:** Search the repo (lib/ and test/) for
  `{:error, :scope_violation` etc. and update; document in
  `CHANGELOG.md`; ship as v0.1.2.
- **Risk:** Adding `:request_id` to all telemetry metadata could
  break listener tests that match metadata maps exactly.
  **Mitigation:** Update internal tests; document the addition in
  `CHANGELOG.md` as "metadata is now `%{... | :request_id}`".
- **Risk:** Refactoring `delegation.ex` into a subdir touches the
  one place callers reach for the function. **Mitigation:** Keep
  `AshHarness.Delegation.initiate/4` as a thin re-export of
  `AshHarness.Delegation.Initiate.run/4`; the external module path
  doesn't change.
- **Risk:** `Splode` is a new dependency. **Mitigation:** Splode is
  already part of Ash's ecosystem (Ash uses it for `Ash.Error`);
  it's a small lib (~few KB). Pin `~> 0.2`.
- **Trade-off:** Four `:checked` events per dispatch increase
  telemetry volume. Worth it for the design alignment and pass-rate
  observability.

## Migration Plan

This is a single change shipped as v0.1.2. No phased rollout needed:

1. Bump `mix.exs` version to `0.1.2`.
2. Add Splode to deps.
3. Build `lib/ash_harness/errors/` first (no callers yet).
4. Switch gates to return struct errors; update repair formatter;
   update tests.
5. Add `request_id` to dispatch; thread through telemetry; update
   tests.
6. Fix `attempt: 1` hardcode; update tests.
7. Add `:checked` pass-events; update telemetry test handlers.
8. Add `:data` field to TrajectoryEntry; update tests.
9. Refactor `delegation.ex` into subdir; build skill; wire into
   `OrchestratorFactory`; integration test the full LLM-to-delegate
   round trip.
10. Update telemetry metadata fields on the existing events.
11. Update design docs (`public-api.md`, ADR 0005, layer 05, 09, 11,
    `module-tree.md`); close resolved open questions.
12. Update `CLAUDE.md`, `README.md`, `CHANGELOG.md`.

Rollback: standard git revert; no migrations, no data shape changes,
no external service contracts touched.

## Open Questions

- **Nested HITL behavior (deferred):** if a delegate halts requesting
  its own confirmation, should the host agent see and forward that
  ApprovalRequest, or should the skill return a text error and let the
  child unblock independently? For v0.1.2 we take the simpler path:
  the skill returns `{:error, "delegate halted: requires confirmation"}`
  and HITL stays at the top agent. Revisit when there's a real
  multi-tier-approval workflow to model. Implementation lives in the
  `Delegation.Skill` (task 9.7); this open question stays open.
- Should the delegation skill enforce a per-call timeout, or rely on
  the child agent's own budget exhausting? Defaulting to "rely on
  child" for v0.1.2 — the child has its own `max_mutations_per_turn`
  and Jido's transport timeout. Revisit if real-world delegation
  chains hang.
- For the `respondent` field on confirmation events: the design
  expects "who approved." Today the confirmation gate doesn't know;
  `Harness.resume/2` receives the decision but the host supplies the
  identity. Plan: thread a `respondent:` key in the
  `%ApprovalResponse{}` (optional, defaults to `:unspecified`);
  `:auto_confirm` modes set it to `:auto_confirm`.
