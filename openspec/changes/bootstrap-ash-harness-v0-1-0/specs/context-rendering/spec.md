# context-rendering — Specification

## ADDED Requirements

### Requirement: Render initial system context

`AshHarness.ContextRenderer.render/2` SHALL produce an
`AshHarness.RenderedContext` struct whose `:initial_text` contains:
agent identity, domain vocabulary (when present), per-resource
**summaries** (one to two lines each), the traversal map (compact),
strategies, delegation hints, constraints, and meta-tools
documentation. Per-resource detail SHALL NOT appear in
`:initial_text`.

#### Scenario: Initial text contains required sections
- **WHEN** `render/2` is called for an agent with annotations and a
  non-empty scope
- **THEN** the resulting `:initial_text` contains the strings for
  identity name, each scoped resource's summary, and at least one
  meta-tool name

#### Scenario: Initial text excludes per-resource detail
- **WHEN** `render/2` is called and the agent scopes a Ticket
- **THEN** the `:initial_text` contains a Ticket summary line but does
  NOT contain the full attribute list, the full action list with all
  hints, or the full schema

### Requirement: Render per-resource detail on demand

`AshHarness.ContextRenderer.render_resource/3` SHALL produce a string
containing: the resource description, attributes (excluding
`hidden_attributes`), scoped actions with hints and policy indicators
(`auto-execute`, `requires confirmation`, `requires reasoning`),
accepted parameters, and traversable connections. The function MUST be
deterministic for a given (agent, resource, actor).

#### Scenario: Hidden attributes excluded
- **WHEN** a resource declares `hidden_attributes [:internal_notes]`
  and `render_resource/3` is called for that resource
- **THEN** `"internal_notes"` does NOT appear anywhere in the output

#### Scenario: Out-of-scope action excluded
- **WHEN** a resource has an action `:resolve` but the agent's scope
  for that resource does NOT include `:resolve`
- **THEN** the rendered detail does NOT mention the `:resolve` action

#### Scenario: Action hint is included
- **WHEN** a resource's `agent_annotations` declare `hint :assign,
  "Delegate work."` and `:assign` is in scope
- **THEN** the rendered detail for the `:assign` action contains the
  string `"Delegate work."`

### Requirement: Action policy indicators

The renderer SHALL indicate per-action policy in the rendered detail:
`(auto-execute)` when the action is in `auto_execute`,
`(requires confirmation)` when in `confirm_before`, and
`(requires reasoning)` when in `require_reasoning_for`. These
indicators MAY combine.

#### Scenario: Action requires confirmation and reasoning
- **WHEN** an action is in both `confirm_before` and
  `require_reasoning_for`
- **THEN** the rendered detail line contains both
  `(requires confirmation)` and `(requires reasoning)`

### Requirement: Pre-filter actions by Ash.can?

`render_resource/3` and `render/2` SHALL support an optional `:actor`
option (defaulting to the agent's identity actor). When an actor is
known and `Ash.can?(actor, resource, action)` deterministically returns
`false`, the action SHALL be omitted from the rendered detail. When
`Ash.can?` returns `true` or `:maybe`, the action SHALL be included.

#### Scenario: Action is denied by Ash policy
- **WHEN** `Ash.can?(actor, MyResource, :destroy)` returns `false`
- **THEN** `:destroy` is omitted from the rendered detail for the
  resource

### Requirement: Token-budget truncation

`render/2` SHALL accept an optional `:token_budget` integer. When the
estimated tokens of the rendered initial text exceed the budget,
sections SHALL be dropped in the order: strategies → delegation hints →
vocabulary. Resource summaries SHALL NEVER be truncated.

#### Scenario: Budget exceeded; strategies dropped first
- **WHEN** the rendered initial text exceeds the budget by an amount
  the strategies section can absorb
- **THEN** the strategies section is removed and the resource summaries
  remain in full

#### Scenario: Budget cannot be met
- **WHEN** the resource summaries alone exceed the budget
- **THEN** the renderer returns the full required sections and surfaces
  a warning in the result struct (no silent truncation of summaries)

### Requirement: Token estimation

The library SHALL include a token-estimation helper used by the
renderer, defaulting to `byte_size(text) / 4` rounded up, with a
configurable `:token_ratio`. The estimator's contract SHALL be that
the same input produces the same output across processes.

#### Scenario: Default token ratio
- **WHEN** the configuration `config :ash_harness, :context,
  token_ratio: 4` is in effect
- **THEN** a 400-byte string estimates to 100 tokens

### Requirement: Caching of rendered output

The renderer SHALL cache rendered initial text and per-resource detail
keyed by `(agent_module, actor_id)`. The cache SHALL invalidate when
the agent module is recompiled.

#### Scenario: Cache hit on second call
- **WHEN** `render/2` is called twice in succession with the same
  agent and actor
- **THEN** the second call returns from cache (observable via reduced
  emission of `[:ash_harness, :context, :rendered]` events or via a
  test double)
