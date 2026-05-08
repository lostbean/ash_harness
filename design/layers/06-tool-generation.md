# Layer 06 — Tool Generation

Two-track strategy:

1. **Compile-time**: per-action `Jido.Action` modules wrapped in
   per-resource `Jido.Composer.Skill` structs.
2. **Runtime**: `AshHarness.Tool.dynamic/2` for session-scoped tools
   (finalizers, conditional tools, etc.).

Both flow through the same canonical schema and the same
scope/policy/budget gates.

## Why two tracks (decision: ADR 0005)

- **Compile-time** wins for the 90% case: every scoped (resource, action)
  pair is a tool. Module-name stack traces. Static schema validation.
- **Runtime** covers cases compile-time cannot:
  - "Submit for review" tool that only exists when there are unsaved
    drafts in the session.
  - Tools whose schema depends on session-time data (e.g., a
    `select_assignee` tool whose enum is filtered by the actor's
    visibility).
  - Composing AshHarness with another library that wants to inject
    its own tool at session start.

## Canonical schema

```elixir
defmodule AshHarness.Schema.Canonical do
  defstruct [
    :resource,           # module
    :action_name,        # atom
    :tool_name,          # "ticket__assign"
    :description,        # combined: hint + action type
    :parameters,         # %{name => %ParamSpec{}}
    :required,           # [name]
    :examples            # [%Example{}], optional
  ]
end

defmodule AshHarness.Schema.ParamSpec do
  defstruct [
    :name,                # atom
    :type,                # JSON-Schema type tag (:string, :integer, :enum, :uuid, etc.)
    :description,         # natural language
    :enum,                # [String.t()] or nil
    :format,              # "uuid" | "date-time" | nil
    :item_type            # for arrays
  ]
end
```

Derived **once** at agent compile time. Three renderers project to:

- Anthropic `input_schema` (JSON Schema 2020-12).
- OpenAI tool `parameters`.
- MCP `inputSchema`.

The canonical artifact is persisted as part of the `:tool_list` DSL
state.

## Tool naming

`{resource_short_name}__{action_name}` — short resource name is the
last segment of the module's atom name, snake_cased. Examples:

- `MyApp.Ticketing.Ticket` + `:assign` → `"ticket__assign"`
- `MyApp.Team.Member` + `:by_workload` → `"member__by_workload"`

Two underscores deconflict from action names that themselves contain
underscores. Reverse-mapping at session start is unambiguous.

If two resources share a short name within the same agent (e.g., two
`Order` modules from different domains), the verifier raises and asks
the agent author to disambiguate via a DSL hint:

```elixir
scope do
  resource MyApp.Sales.Order, alias: "sales_order" do
    actions [:read]
  end
  resource MyApp.Returns.Order, alias: "return_order" do
    actions [:read]
  end
end
```

(Only needed in conflict cases; default name from module suffix.)

## Type mapping (Ash → JSON Schema)

| Ash type | JSON Schema |
| --- | --- |
| `:string` | `{"type": "string"}` |
| `:integer` | `{"type": "integer"}` |
| `:float` | `{"type": "number"}` |
| `:boolean` | `{"type": "boolean"}` |
| `:uuid` | `{"type": "string", "format": "uuid"}` |
| `:atom` with `one_of` | `{"type": "string", "enum": [...]}` |
| `:utc_datetime`, `:utc_datetime_usec` | `{"type": "string", "format": "date-time"}` |
| `:date` | `{"type": "string", "format": "date"}` |
| `:time`, `:time_usec` | `{"type": "string", "format": "time"}` |
| `:decimal` | `{"type": "string", "description": "decimal as string"}` |
| `:map`, `:keyword_list` | `{"type": "object"}` |
| `{:array, inner}` | `{"type": "array", "items": <mapped inner>}` |
| `Ash.Type.NewType` (custom) | resolved to underlying primitive when possible |
| Embedded resources | `{"type": "object", "properties": {…}}` recursively |

Constraints: `min`, `max`, `min_length`, `max_length` propagate to JSON
Schema where supported.

## Compile-time generation

For each `(resource, action)` in scope, AshHarness generates:

```elixir
# inside MyAgent's compile pipeline
defmodule MyAgent.Tools.Ticket.Assign do
  use Jido.Action,
    name:        "ticket__assign",
    description: "Delegate work to a team member. (update on Ticket)",
    schema:      <derived NimbleOptions schema from Canonical>

  @resource     MyApp.Ticketing.Ticket
  @action_name  :assign
  @canonical    <Canonical struct>

  @impl Jido.Action
  def run(input, ctx) do
    AshHarness.Harness.GeneratedAction.dispatch(
      @resource, @action_name, @canonical, input, ctx
    )
  end
end
```

`AshHarness.Harness.GeneratedAction.dispatch/5` is the shared body that
runs the gates and the executor. Generated modules are *thin* — they
only declare schema/metadata; logic lives in the harness.

## Skill generation

```elixir
defmodule MyAgent.Skills do
  def ticket do
    %Jido.Composer.Skill{
      name:            "ticket",
      description:     "A work item tracking a bug, feature, or task.",
      prompt_fragment: AshHarness.ContextRenderer.render_resource(MyAgent, MyApp.Ticketing.Ticket),
      tools: [
        MyAgent.Tools.Ticket.Read,
        MyAgent.Tools.Ticket.OpenTicket,
        MyAgent.Tools.Ticket.Assign
      ]
    }
  end

  def project do
    # …
  end

  def all, do: [ticket(), project(), member()]
end
```

Skills are evaluated at session start (not compile time) so the
`prompt_fragment` reflects current cached context render.

## Runtime dynamic tools

```elixir
defmodule AshHarness.Tool do
  @doc """
  Builds a Jido.Action at runtime, using the same gate pipeline as
  compile-time tools.

  ## Example

      def session_tools(session) do
        if has_unsaved_draft?(session) do
          [
            AshHarness.Tool.dynamic("ticket__finalize_draft",
              description: "Finalize the unsaved draft as a real ticket.",
              schema: [reason: [type: :string, required: true]],
              resource: MyApp.Ticketing.Ticket,
              action:   :open_ticket,
              input_builder: fn input, session ->
                Map.merge(session.draft, input)
              end
            )
          ]
        else
          []
        end
      end
  """
  @spec dynamic(String.t(), keyword()) :: Jido.Action.t()
  def dynamic(tool_name, opts)
end
```

The dynamic tool wraps an Ash action call exactly like a generated one;
it just lets the host app shape the input at runtime. All gates apply.

## Security implications

The agent **never** sees a tool for an action it can't invoke. The
toolset for a session is the union of:

- compile-time tools for in-scope (resource, action) pairs;
- runtime dynamic tools registered by the host app at session start.

If a runtime tool calls an Ash action outside the agent's static scope,
the scope gate rejects at execution time. The host app cannot
accidentally widen the agent's authority via dynamic tools — they are
subject to the same scope check.

## Open questions

- **Should we generate a `read` tool with filter parameters
  auto-derived from public attributes?** Spec'd as: yes. Read actions
  accept a `filter` map keyed by public attributes; at execution we
  build the corresponding `Ash.Query`. Detail the filter param shape in
  v0.1.0.
- **What about generic actions?** Treat the same as CRUD actions — they
  have arguments, they have a return type, they map to a tool. The only
  oddity is that they may not return an `Ash.Resource` instance.
- **Should there be a way to **rename** a tool (override the
  `resource__action` default) for clarity?** Yes — add an `as:` option
  on the `actions` macro inside `scope`:
  ```elixir
  scope do
    resource Ticket do
      actions [:read, {:assign, as: "delegate"}]
    end
  end
  ```
  Defer to v0.2 unless a test case demands it.
