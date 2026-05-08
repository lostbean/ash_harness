# agent-dsl — Specification

## ADDED Requirements

### Requirement: Agent declaration entry point

A module that calls `use AshHarness.Agent, domains: [<domains>]` SHALL
become an agent module exposing the AshHarness DSL. The macro SHALL
accept a required `domains:` keyword option listing one or more Ash
domain modules.

#### Scenario: Agent declares with one domain
- **WHEN** a module declares `use AshHarness.Agent, domains:
  [MyApp.Ticketing]` and provides identity, scope, and behavior
- **THEN** compilation succeeds and `AshHarness.Agent.Info.domains/1`
  returns `[MyApp.Ticketing]`

#### Scenario: Agent declares without domains
- **WHEN** a module declares `use AshHarness.Agent` without `domains:`
- **THEN** compilation fails with a message stating that `domains:` is
  required

### Requirement: Identity section

The agent DSL SHALL provide a required `identity` section with
required keys `name :: String`, `description :: String`, and `actor ::
any()`, plus an optional key `model :: String | nil`. The `actor` MAY
be a struct, a 0-arity function, or an MFA tuple — resolved at session
start, not compile time.

#### Scenario: Identity with all fields
- **WHEN** an agent declares `identity do name "..." ; description
  "..." ; actor my_actor() ; model "anthropic:claude-sonnet-4-5" end`
- **THEN** all four values are accessible via
  `AshHarness.Agent.Info.{name,description,actor,model}/1`

#### Scenario: Identity missing required field
- **WHEN** an agent omits `name`, `description`, or `actor` in
  `identity`
- **THEN** compilation fails with a message naming the missing key

### Requirement: Scope section

The agent DSL SHALL provide a `scope` section containing zero or more
`resource <module> do actions [<atoms>] end` entries. Each entry SHALL
declare a resource module and a non-empty list of action atoms the
agent is permitted to invoke. The scope SHALL be non-empty: an agent
with no scope entries SHALL fail to compile.

#### Scenario: Scope with one resource and three actions
- **WHEN** an agent declares `scope do resource Ticket do actions
  [:read, :open_ticket, :assign] end end`
- **THEN** `AshHarness.Agent.Info.scoped_actions(MyAgent, Ticket)`
  returns `[:read, :open_ticket, :assign]` and
  `AshHarness.Agent.Info.in_scope?(MyAgent, Ticket, :assign)` returns
  `true`

#### Scenario: Empty scope
- **WHEN** an agent declares an empty `scope do end` block
- **THEN** compilation fails with a message stating that the scope must
  not be empty

#### Scenario: Action not in scope
- **WHEN** `AshHarness.Agent.Info.in_scope?(MyAgent, Ticket, :destroy)`
  is called and `:destroy` is not listed for `Ticket` in the agent's
  scope
- **THEN** the function returns `false`

### Requirement: Behavior section

The agent DSL SHALL provide a `behavior` section accepting
`confirm_before :: [atom]` and `auto_execute :: [atom]` keys plus zero
or more `strategy <name>, <description>` entities. An action SHALL NOT
appear in both `confirm_before` and `auto_execute`.

#### Scenario: Behavior declares conflicting policy
- **WHEN** an agent declares `confirm_before [:assign]` and
  `auto_execute [:assign]` together
- **THEN** compilation fails with a message naming the conflicting
  action

#### Scenario: Strategy is exposed
- **WHEN** an agent declares `strategy :default, "..."` in its
  `behavior` block
- **THEN** `AshHarness.Agent.Info.strategies(MyAgent)` returns a list
  containing `%Strategy{name: :default, description: "..."}`

### Requirement: Delegates_to section

The agent DSL SHALL provide a `delegates_to` section containing zero
or more `delegate <agent_module>, for: <description>` entries. Each
delegate target module SHALL itself be a module that uses
`AshHarness.Agent`.

#### Scenario: Delegate target is not an AshHarness agent
- **WHEN** an agent declares `delegate NotAnAgent, for: "..."` and
  `NotAnAgent` does not use `AshHarness.Agent`
- **THEN** compilation fails with a message naming the offending module

#### Scenario: Delegates are exposed
- **WHEN** an agent declares two delegate entries
- **THEN** `AshHarness.Agent.Info.delegates(MyAgent)` returns both
  entries as `%DelegateEntry{agent_module: ..., for: ...}` structs

### Requirement: Constraints section

The agent DSL SHALL provide a `constraints` section accepting
`max_mutations_per_turn :: non_neg_integer` (default 10),
`require_reasoning_for :: [atom]` (default `[]`), `max_context_tokens
:: non_neg_integer` (default 128_000), and `max_repair_loop_retries ::
non_neg_integer` (default 3). All keys SHALL have safe defaults so the
section is optional.

#### Scenario: Constraints not declared
- **WHEN** an agent omits the `constraints` section
- **THEN** the introspection functions return the default values listed
  above

#### Scenario: Constraint values are exposed
- **WHEN** an agent declares `max_mutations_per_turn 5`
- **THEN** `AshHarness.Agent.Info.max_mutations_per_turn(MyAgent)`
  returns `5`

### Requirement: Cross-section compile-time validation

The agent module SHALL fail to compile when:
- a resource in `scope` does not belong to a domain in the agent's
  `domains:` list,
- an action in `scope` does not exist on its declared resource,
- an action in `confirm_before`, `auto_execute`, or
  `require_reasoning_for` does not appear in any scope entry,
- a delegate module does not use `AshHarness.Agent`,
- two domains in the agent's `domains:` list both define a `term` with
  the same `word`.

These checks SHALL run as Spark verifiers, after all transformers have
persisted derived data.

#### Scenario: Scoped resource not in any declared domain
- **WHEN** the agent's scope lists a resource whose Ash domain is not
  in the agent's `domains:` list
- **THEN** compilation fails with a message naming the resource, its
  domain, and noting that the domain is not in the agent's domain list

#### Scenario: Scoped action does not exist
- **WHEN** the agent's scope declares `actions [:nonexistent]` for a
  resource that has no `:nonexistent` action
- **THEN** compilation fails with a message naming the action and the
  resource

#### Scenario: Confirm_before lists an out-of-scope action
- **WHEN** the agent declares `confirm_before [:destroy]` but no scope
  entry exposes `:destroy`
- **THEN** compilation fails with a message naming the action

#### Scenario: Two domains share a term word
- **WHEN** the agent declares `domains: [A, B]` and both domains define
  a `term "invoice", ...` entry
- **THEN** compilation fails with a message naming the term and both
  domains

### Requirement: Agent module introspection

The `AshHarness.Agent.Info` module SHALL expose introspection for
every DSL element: `name/1`, `description/1`, `actor/1`, `model/1`,
`domains/1`, `scope_entries/1`, `scoped_resources/1`,
`scoped_actions/2`, `in_scope?/3`, `confirm_before/1`,
`auto_execute/1`, `confirms_action?/2`, `strategies/1`, `delegates/1`,
`delegate_for?/2`, `max_mutations_per_turn/1`,
`max_context_tokens/1`, `max_repair_loop_retries/1`,
`require_reasoning_for/1`, `reasoning_required?/2`,
`reachability_graph/1`, and `tool_list/1`.

#### Scenario: Reachability graph is persisted
- **WHEN** `AshHarness.Agent.Info.reachability_graph(MyAgent)` is
  called on a compiled agent
- **THEN** the function returns the graph computed by the
  `ComputeReachability` transformer (no recomputation)

#### Scenario: Tool list is persisted
- **WHEN** `AshHarness.Agent.Info.tool_list(MyAgent)` is called on a
  compiled agent
- **THEN** the function returns the canonical-schema list computed by
  the `ComputeToolSet` transformer
