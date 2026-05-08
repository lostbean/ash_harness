# tool-generation — Specification

## ADDED Requirements

### Requirement: Compile-time Jido.Action emission

For each `(resource, action)` pair in an agent's scope, the library
SHALL emit a `Jido.Action` module at compile time. The emitted module
SHALL declare the canonical schema as its `schema:` and SHALL implement
`run/2` by delegating to
`AshHarness.Harness.GeneratedAction.dispatch/5` with the resource
module, action name, canonical schema, the input, and the orchestrator
context.

#### Scenario: One module per scoped action
- **WHEN** an agent's scope contains three actions on resource `Ticket`
- **THEN** three modules exist after compilation:
  `MyAgent.Tools.Ticket.Read`, `MyAgent.Tools.Ticket.OpenTicket`, and
  `MyAgent.Tools.Ticket.Assign`, each `use Jido.Action`

#### Scenario: Generated run/2 dispatches to harness
- **WHEN** an emitted module's `run/2` is invoked with input and ctx
- **THEN** the call delegates to
  `AshHarness.Harness.GeneratedAction.dispatch/5` with the bound
  resource and action; no Ash call happens directly inside `run/2`

### Requirement: Compile-time Skill emission

For each scoped resource, the library SHALL emit one
`Jido.Composer.Skill` value containing the resource's name (string),
description, prompt fragment (the rendered resource detail), and the
list of generated `Jido.Action` modules for that resource.

#### Scenario: One skill per scoped resource
- **WHEN** an agent's scope contains resources Ticket, Project, and
  Member
- **THEN** the agent exposes three skills, one per resource, each
  containing its actions as tools

#### Scenario: Skill prompt fragment reflects rendered detail
- **WHEN** a skill is materialized at session start
- **THEN** its `prompt_fragment` equals
  `AshHarness.ContextRenderer.render_resource(MyAgent, ResourceModule)`

### Requirement: Runtime dynamic tool API

The library SHALL provide `AshHarness.Tool.dynamic/2` that builds a
`Jido.Action`-compatible value at session-start time. Dynamic tools
SHALL accept a name (string), a description, a schema (NimbleOptions or
keyword equivalent), an `input_builder` function (or a fixed
`(resource, action)` mapping), and SHALL flow through the same
scope/reasoning/budget/policy gate pipeline as compile-time tools.

#### Scenario: Dynamic tool is gated
- **WHEN** a dynamic tool wraps an Ash action that is NOT in the
  agent's static scope
- **THEN** invocation fails at the scope gate with the same
  `:scope_violation` outcome as a compile-time tool would

#### Scenario: Dynamic tool input_builder transforms input
- **WHEN** a dynamic tool declares an `input_builder` that merges the
  session's metadata with the LLM-provided input before dispatch
- **THEN** the merged map is passed to the Ash action executor

### Requirement: Tool dispatch parity

Compile-time and runtime tools SHALL produce identical results when
invoking the same underlying Ash action with the same input and actor.
The harness SHALL NOT differentiate the two at the gate-pipeline level.

#### Scenario: Identical outcomes for compile vs dynamic
- **WHEN** the same Ash action is invoked once via a compile-time tool
  and once via a dynamic tool with equivalent input
- **THEN** both produce equal `%AshHarness.Harness.Result{}` values
  modulo timing fields
