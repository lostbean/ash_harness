# Layer 05 — Context Renderer

Reads the agent definition, scoped resources, the reachability graph, and
the actor's policy permissions to produce the agent's system prompt.

## Purpose

Convert a declarative agent module into the natural-language briefing the
LLM sees. The output is structured, sectioned, and — with progressive
disclosure — initially compact.

## Output structure

The implementation collapses the design's original per-section fields
into the four fields the rest of the runtime actually reads. The
section-level data lives in the composed `initial_text` string.

```elixir
defmodule AshHarness.RenderedContext do
  defstruct [
    :initial_text,
    :token_estimate,
    resource_details: %{},
    warnings: []
  ]

  @type t :: %__MODULE__{
    initial_text:     String.t(),
    token_estimate:   non_neg_integer(),
    resource_details: %{module() => String.t()},
    warnings:         [String.t()]
  }
end
```

`initial_text` is the concatenated initial context (identity, vocabulary,
resource summaries, traversal map, strategies, delegation hints,
constraints, meta-tools doc). `resource_details` is a map of module →
expanded detail string, loaded on demand by `load_resource_skill`.
`warnings` carries any non-fatal renderer notes (e.g. "token budget
truncated strategies section"). Per-section composition is done by
private helpers in `lib/ash_harness/context_renderer.ex` rather than the
sub-module layout the design originally sketched.

## Initial vs expanded

| Section | When |
| --- | --- |
| Identity | always |
| Vocabulary | always (if any terms defined) |
| Resource **summaries** (1-2 lines each) | always |
| Traversal map (compact) | always |
| Strategies | always |
| Delegation hints | always |
| Constraints | always |
| Meta-tools docs (`load_resource_skill`) | always |
| Resource **detail** (full attrs, all action hints, full schema) | on `load_resource_skill(:resource)` |

This split matches the progressive disclosure mechanism (ADR 0007).

## Public API

```elixir
defmodule AshHarness.ContextRenderer do
  @spec render(module(), keyword()) :: AshHarness.RenderedContext.t()
  def render(agent_module, opts \\ [])

  @spec render_resource(module(), module(), term() | nil) :: String.t()
  def render_resource(agent_module, resource_module, actor \\ nil)
end
```

`render_resource/3` takes the actor directly. The design originally
specified an `opts` keyword form; the implementation went with the
plainer `actor` arg because the only caller (`load_resource_skill`)
just forwards the session actor. The `opts` form is deferred to v0.2
if a second caller appears that needs more knobs.

No `resource_summary/2` is exposed — `render/2` already populates
`RenderedContext.resource_details[module]` with the per-resource detail
strings, and there's no scenario in the codebase that wants a separate
summary-only call. If one appears in v0.2, it'll be a thin wrapper
over the section composer.

### Options

- `:actor` — if provided, the renderer pre-filters actions via `Ash.can?`
  and excludes definitely-unauthorized actions from the rendered detail.
  Defaults to the actor declared in the agent's identity.
- `:token_budget` — optional cap. If exceeded, sections are dropped in
  this order: strategies → delegation hints → vocabulary. Resource
  summaries are **never truncated**.
- `:include_examples` — boolean (default false). When true, the renderer
  injects one-line example tool invocations per action (when annotations
  provide them).

## Section formats

### Identity

```
You are: Triage Agent
What you do: Processes incoming tickets and assigns ownership.
```

### Vocabulary

```
Domain vocabulary:
- ticket — A discrete unit of work. A bug, feature request, or task.
- triage — The process of assessing priority and assigning ownership.
- blocker — A ticket whose resolution is required before other tickets can proceed.
```

### Resource summaries (initial context)

```
Resources you can use (call `load_resource_skill(:name)` to load full detail):

- ticket  — A work item tracking a bug, feature, or task.
            Connections: project, comments
- project — A grouping of related tickets.
            Connections: tickets
- member  — A team member who can be assigned tickets.
```

### Resource detail (loaded on demand)

```
## Ticket
A work item tracking a bug, feature, or task.

Attributes:
- id: uuid (primary key)
- title: string (required)
- status: one of [:open, :in_progress, :resolved]
- priority: one of [:low, :medium, :high, :critical]
- assigned_to: uuid (optional)
- inserted_at: utc_datetime
- updated_at: utc_datetime

Actions:
- read (auto-execute)
    Type: read
    Returns a list of tickets. Supports standard filtering.

- open_ticket (auto-execute)
    Type: create
    Hint: Use when someone reports a new issue.
    Accepts: title (string, required), priority (one of low/medium/high/critical), project_id (uuid)

- assign (requires confirmation, requires reasoning)
    Type: update
    Hint: Delegate work to a team member.
    Accepts: id (uuid, required), assigned_to (uuid, required)
    Side effects: Sets status to :in_progress automatically.

Connections:
- project → Project (belongs_to) — can traverse
- comments → Comment (has_many) — can traverse
```

### Traversal map (initial)

```
Connections in your scope:
- ticket  → project (1:1), comments (1:N)
- project → tickets (1:N)
- member  has no traversable connections
```

### Strategies

```
Strategies:
- default: Check overdue first, then unassigned, sort by severity.
```

### Delegation hints

```
You can delegate to:
- BillingAgent — for customer account status checks
- IncidentAgent — for incident escalations
```

### Constraints

```
Operating limits:
- At most 5 mutations per turn (creates/updates/destroys).
- Actions requiring reasoning before execution: assign.
- Maximum context: 128,000 tokens. Older steps may be summarized.
```

### Meta-tools doc (initial)

```
Available meta-tools:
- load_resource_skill(name): expand the full detail and tool set for a resource.
- inspect_resource(name): same as load_resource_skill but read-only.
```

## Rendering rules

1. **Attribute rendering:** name, Ash type as human-readable string,
   `one_of` values inlined, `required` indicator, exclude
   `hidden_attributes`. Primary keys are listed but not in any "Accepts"
   list (they're auto-generated for create; auto-required for
   update/destroy).
2. **Action rendering:**
   - Show action type, accepted args with types.
   - Show hint text from `agent_annotations.hint`.
   - Indicator: `(auto-execute)`, `(requires confirmation)`, `(requires
     reasoning)`.
   - Human-readable validation summary (best-effort from Ash's validation
     metadata; fall back to "may have validations" if unparseable).
3. **Relationship rendering:** only those in the reachability graph.
   Show direction and destination resource.
4. **Ordering:**
   - Resources alphabetical.
   - Attributes in declaration order.
   - Actions: reads → creates → updates → destroys → generic.
5. **Pre-filtering by `Ash.can?`** (when actor known): if `Ash.can?(actor,
   resource, action)` deterministically returns false, the action is
   omitted from the rendered detail. (Note: many policies return `:maybe`
   without input data — we render those.)

## Token estimation

Rough heuristic: `byte_size(text) / 4`. Configurable via
`config :ash_harness, :context, token_ratio: 4`. v0.1.0 does not use a
real tokenizer; if/when needed, swap in a tokenizer behaviour.

## Caching

- The **initial_text** for an agent is stable across sessions (modulo
  actor-dependent filtering). The renderer caches it per
  `(agent_module, actor_id)` in an ETS table for the application's
  lifetime.
- Per-resource detail is cached the same way.
- Cache invalidates on agent module recompilation (track via
  `:beam_lib.module_md5/1` or `Module.module_info(:md5)`).

## Open questions

- **Should we render Ash calculations and aggregates as virtual
  attributes?** v0.1.0: yes for public ones, marked `(calculated)`.
- **Should we render relationship arity in the summary line, like `1:N`?**
  Yes; helps the model know what shape of result to expect.
- **Should we render an `ash_can_filter?` hint per action?** Defer.
  Filtering is implicit in `:read` actions.
