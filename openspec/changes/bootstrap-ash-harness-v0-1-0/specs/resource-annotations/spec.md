# resource-annotations — Specification

## ADDED Requirements

### Requirement: Resource annotation DSL

The `AshHarness.Resource` Spark DSL extension SHALL provide an
`agent_annotations` section on Ash resources with: a required
`description` (string), an optional `traversable` list of relationship
names, an optional `hidden_attributes` list of attribute names, and zero
or more `hint` entities of `(action_name :: atom, text :: String)`.

#### Scenario: Resource declares full annotations
- **WHEN** a resource uses `extensions: [AshHarness.Resource]` and
  declares `agent_annotations do … end` with description, traversable,
  hidden_attributes, and one hint
- **THEN** compilation succeeds and the resource exposes all four pieces
  of metadata via introspection

#### Scenario: Resource omits the extension
- **WHEN** a resource does not use the `AshHarness.Resource` extension
- **THEN** `AshHarness.Resource.Info.agent_annotated?/1` returns
  `false`, `description/1` returns `nil`, `hints/1` returns `[]`,
  `traversable/1` returns `[]`, and `hidden_attributes/1` returns `[]`

### Requirement: Resource annotation introspection

The `AshHarness.Resource.Info` module SHALL expose
`description/1`, `hints/1`, `hint_for/2`, `traversable/1`,
`hidden_attributes/1`, and `agent_annotated?/1`. All functions SHALL
accept either a resource module or a Spark DSL state.

#### Scenario: Lookup hint by action name
- **WHEN** `AshHarness.Resource.Info.hint_for(MyResource, :assign)` is
  called and a hint with `action_name: :assign` is declared
- **THEN** the hint's `text` field is returned as a string

#### Scenario: Lookup hint that does not exist
- **WHEN** `AshHarness.Resource.Info.hint_for(MyResource, :nonexistent)`
  is called and no matching hint exists
- **THEN** `nil` is returned

### Requirement: Resource annotation compile-time validation

The extension SHALL refuse to compile when annotations reference
resource elements that do not exist. Specifically: every `hint`'s
`action_name` MUST correspond to an action declared on the resource;
every atom in `traversable` MUST correspond to a relationship; every
atom in `hidden_attributes` MUST correspond to an attribute. Validation
SHALL run in a Spark verifier (after all transformers).

#### Scenario: Hint references a non-existent action
- **WHEN** a resource declares `hint :foo, "..."` but no action `:foo`
  exists on the resource
- **THEN** compilation fails with a message naming the action and the
  resource module

#### Scenario: Traversable references a non-existent relationship
- **WHEN** a resource declares `traversable [:bar]` but no relationship
  `:bar` exists
- **THEN** compilation fails with a message naming the relationship and
  the resource

#### Scenario: Hidden attribute references a non-existent attribute
- **WHEN** a resource declares `hidden_attributes [:baz]` but no
  attribute `:baz` exists
- **THEN** compilation fails with a message naming the attribute and
  the resource

### Requirement: Hint entity struct

The library SHALL provide an `AshHarness.Resource.Hint` struct with
fields `:action_name` (atom) and `:text` (string), used as the target
type for parsed hint entities and returned by introspection functions.

#### Scenario: Inspect a hint
- **WHEN** `AshHarness.Resource.Info.hints(MyResource)` returns hints
- **THEN** each element is a `%AshHarness.Resource.Hint{action_name:
  atom, text: String.t()}` struct
