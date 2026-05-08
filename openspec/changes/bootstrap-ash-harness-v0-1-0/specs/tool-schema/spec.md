# tool-schema — Specification

## ADDED Requirements

### Requirement: Canonical schema artifact

The library SHALL provide an `AshHarness.Schema.Canonical` struct
derived once at agent compile time per scoped (resource, action) pair.
The struct SHALL contain `:resource` (module), `:action_name` (atom),
`:tool_name` (string), `:description` (string), `:parameters`
(map of name to ParamSpec), `:required` (list of atoms), and optional
`:examples` (list of structured examples).

#### Scenario: One canonical struct per scoped action
- **WHEN** an agent's scope contains three actions on a resource
- **THEN** `AshHarness.Agent.Info.tool_list/1` returns three canonical
  structs, one per (resource, action) pair

### Requirement: Parameter spec

The library SHALL provide an `AshHarness.Schema.ParamSpec` struct with
fields `:name` (atom), `:type` (canonical type tag),
`:description` (string), `:enum` (list of strings or `nil`),
`:format` (string or `nil`), and `:item_type` (recursive ParamSpec or
`nil`, used for arrays).

#### Scenario: ParamSpec for an enum attribute
- **WHEN** an Ash attribute is `:atom` typed with `one_of: [:open,
  :closed]`
- **THEN** the corresponding ParamSpec has `:type == :enum`, `:enum ==
  ["open", "closed"]`, and `:format == nil`

### Requirement: Tool naming

Each canonical schema SHALL have a `:tool_name` of the form
`"<resource_short_name>__<action_name>"`, where the resource short
name is the snake-cased last segment of the resource's module name
joined with the action atom converted to a string.

#### Scenario: Default tool name
- **WHEN** the resource is `MyApp.Ticketing.Ticket` and the action is
  `:assign`
- **THEN** the tool name is `"ticket__assign"`

#### Scenario: Resource short-name conflict
- **WHEN** an agent's scope contains two resources whose module names
  end in the same segment (`MyApp.Sales.Order` and `MyApp.Returns.Order`)
- **THEN** compilation fails with a message naming the conflict and
  hinting at the per-resource `as: "..."` alias option

### Requirement: Ash type to JSON Schema mapping

The library SHALL provide a deterministic mapping from Ash attribute
and argument types to JSON-Schema type tags, covering at minimum:
`:string`, `:integer`, `:float`, `:boolean`, `:uuid` (format `"uuid"`),
`:atom` with `one_of` (mapped to `enum`), `:utc_datetime` and
`:utc_datetime_usec` (format `"date-time"`), `:date`, `:time`,
`:decimal` (mapped to `string` with description), `:map` and
`:keyword_list` (mapped to `object`), `{:array, inner}` (mapped to
`array` with mapped inner type), and embedded resources (mapped to
`object` recursively).

#### Scenario: Mapping :atom with one_of constraint
- **WHEN** an attribute is `:atom` with `constraints: [one_of: [:open,
  :closed]]`
- **THEN** the canonical ParamSpec has `:type == :enum` and `:enum ==
  ["open", "closed"]`

#### Scenario: Mapping {:array, :string}
- **WHEN** an argument is `{:array, :string}`
- **THEN** the canonical ParamSpec has `:type == :array`,
  `:item_type.type == :string`

### Requirement: Provider-format renderers

The library SHALL provide three pure renderer modules that project a
canonical struct into provider-specific shapes:
`AshHarness.Schema.Render.Anthropic` (Anthropic Messages API
`input_schema`), `AshHarness.Schema.Render.OpenAI` (OpenAI tools
`parameters`), and `AshHarness.Schema.Render.MCP` (MCP `inputSchema`).
Each renderer SHALL accept a canonical struct and return a map.

#### Scenario: Anthropic renderer round-trip
- **WHEN** a canonical struct describes an action with two required
  parameters of type `:string` and `:uuid`
- **THEN** `AshHarness.Schema.Render.Anthropic.render(canonical)`
  returns a map with `"name"`, `"description"`, and an
  `"input_schema"` of `"type": "object"` containing the two parameters
  with correct types and the `"required"` list

#### Scenario: Renderers are pure functions
- **WHEN** the same canonical struct is rendered twice
- **THEN** the two outputs are equal
