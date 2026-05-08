# Layer 03 — `AshHarness.Agent` DSL

The top-level `use AshHarness.Agent` macro defines an agent as a
declarative module. Identity, scope, behavior, delegation graph,
constraints — all stated in one place.

## Purpose

An agent is **not** an Ash resource. It does not live in a domain. It has
no data layer. It is a behavioral declaration:

- *Who* is this agent? (identity)
- *What* can it see and do? (scope)
- *How* does it behave? (strategies, confirmations, auto-execution)
- *Whom* can it ask for help? (delegation)
- *What* are its limits? (constraints)

## Top-level usage

```elixir
defmodule MyApp.Agents.TriageAgent do
  use AshHarness.Agent,
    domains: [MyApp.Ticketing, MyApp.Team]

  identity do
    name "Triage Agent"
    description "Processes incoming tickets and assigns ownership."
    actor MyApp.Agents.Actors.triage_bot()
    model "anthropic:claude-sonnet-4-20250514"
  end

  scope do
    resource MyApp.Ticketing.Ticket do
      actions [:read, :open_ticket, :assign]
    end

    resource MyApp.Team.Member do
      actions [:read, :by_workload]
    end
  end

  behavior do
    confirm_before [:assign]
    auto_execute   [:read]

    strategy :default,
      "Check overdue first, then unassigned, sort by severity."
  end

  delegates_to do
    delegate MyApp.Agents.BillingAgent,
      for: "customer account status checks"
  end

  constraints do
    max_mutations_per_turn   5
    require_reasoning_for    [:assign]
    max_context_tokens       128_000
    max_repair_loop_retries  3
  end
end
```

## Sections

### `identity`

```elixir
identity do
  name        :: String.t()        # required, human label
  description :: String.t()        # required, what this agent does
  actor       :: any()             # required, Ash actor for policy eval
  model       :: String.t() | nil  # optional, Jido model string;
                                   # default from config :ash_harness, :default_model
end
```

The `actor` can be:

- A struct (e.g., `%MyApp.User{id: "agent-001", role: :triage_bot}`).
- A 0-arity function returning a struct (`fn -> resolve_actor() end`).
- An MFA tuple (`{Mod, :fun, []}`).
- An anonymous map for system-level agents (`%{id: "bot", type: :system}`).

The actor is resolved at session start, not at compile time. Function/MFA
forms enable per-tenant or per-user agent instantiation.

### `scope`

```elixir
scope do
  resource ResourceModule do
    actions [atom()]   # required, declared scope of permitted actions
  end
  # zero or more resource entries
end
```

**Empty scope is invalid** — agents that can't do anything aren't useful;
the verifier will raise.

A given resource module appears at most once in a scope.

### `behavior`

```elixir
behavior do
  confirm_before :: [atom()]   # actions requiring user approval
  auto_execute   :: [atom()]   # actions executable without approval
  # zero or more strategy entries
  strategy name :: atom(), description :: String.t()
end
```

Actions not listed in either `confirm_before` or `auto_execute` get the
**default policy from config** (`config :ash_harness, default_action_policy:
:auto_execute | :confirm_before`). The default of the default is
`:auto_execute` for `:read` actions and `:confirm_before` for
write actions, but installations can change this.

### `delegates_to`

```elixir
delegates_to do
  delegate AgentModule, for: String.t()
  # zero or more
end
```

`for:` is a natural-language description of what this delegate handles
— surfaced in the agent's context so the LLM knows when to delegate.
**The delegate uses its own scope at delegation time** (anti-corruption,
ADR 0004).

### `constraints`

```elixir
constraints do
  max_mutations_per_turn   :: non_neg_integer()  # default 10
  require_reasoning_for    :: [atom()]           # default []
  max_context_tokens       :: non_neg_integer()  # default 128_000
  max_repair_loop_retries  :: non_neg_integer()  # default 3
end
```

## Entity structs

```elixir
defmodule AshHarness.Agent.Identity do
  defstruct [:name, :description, :actor, :model]

  @type t :: %__MODULE__{
    name: String.t(),
    description: String.t(),
    actor: any(),
    model: String.t() | nil
  }
end

defmodule AshHarness.Agent.Scope.ResourceEntry do
  defstruct [:module, :actions]

  @type t :: %__MODULE__{module: module(), actions: [atom()]}
end

defmodule AshHarness.Agent.Behavior.Strategy do
  defstruct [:name, :description]

  @type t :: %__MODULE__{name: atom(), description: String.t()}
end

defmodule AshHarness.Agent.Delegation.DelegateEntry do
  defstruct [:agent_module, :for]

  @type t :: %__MODULE__{agent_module: module(), for: String.t()}
end
```

## Compile-time validation (verifiers, run after transformers)

| Verifier | Error |
| --- | --- |
| `ScopeResourcesInDomains` | `"Resource MyApp.Billing.Invoice belongs to domain MyApp.Billing, which is not in this agent's domains list."` |
| `ScopeActionsExist` | `"Action :assign does not exist on MyApp.Ticketing.Ticket."` |
| `ScopeNotEmpty` | `"Scope is empty. An agent must have at least one (resource, action) pair."` |
| `ConfirmBeforeInScope` | `"Action :destroy is in confirm_before but no scoped resource exposes :destroy."` |
| `AutoExecuteInScope` | same shape for `auto_execute` |
| `ConfirmAutoMutuallyExclusive` | `"Action :assign appears in both confirm_before and auto_execute."` |
| `ReasoningActionsInScope` | same shape for `require_reasoning_for` |
| `DelegatesUseAshHarnessAgent` | `"MyApp.Agents.BillingAgent is listed in delegates_to but does not use AshHarness.Agent."` |
| `DomainTermsNoConflict` | `"Domain MyApp.Ticketing and MyApp.Billing both define term 'invoice'."` |

## Transformers (run before verifiers)

`ComputeReachability` — builds the reachability graph and persists it to
DSL state under `:reachability_graph`.

`ComputeToolSet` — for each (resource, action) in scope, builds the
canonical schema and persists the tool list under `:tool_list` (a list
of tuples `{resource_module, action_name, %Schema.Canonical{}}`).

These run before verifiers because verifiers may read the persisted
state. They also run *after* Ash's own transformers (we declare
`after?/1` to wait for `Ash.Resource.Transformers.SetPrimaryActions`),
to ensure all action metadata is final.

## Introspection — `AshHarness.Agent.Info`

```elixir
@spec name(module()) :: String.t()
@spec description(module()) :: String.t()
@spec actor(module()) :: any()
@spec model(module()) :: String.t() | nil
@spec domains(module()) :: [module()]
@spec scope_entries(module()) :: [ResourceEntry.t()]
@spec scoped_resources(module()) :: [module()]
@spec scoped_actions(module(), module()) :: [atom()]
@spec in_scope?(module(), module(), atom()) :: boolean()
@spec confirm_before(module()) :: [atom()]
@spec auto_execute(module()) :: [atom()]
@spec confirms_action?(module(), atom()) :: boolean()
@spec strategies(module()) :: [Strategy.t()]
@spec delegates(module()) :: [DelegateEntry.t()]
@spec delegate_for?(module(), module()) :: boolean()
@spec max_mutations_per_turn(module()) :: non_neg_integer()
@spec max_context_tokens(module()) :: non_neg_integer()
@spec max_repair_loop_retries(module()) :: non_neg_integer()
@spec require_reasoning_for(module()) :: [atom()]
@spec reasoning_required?(module(), atom()) :: boolean()
@spec reachability_graph(module()) :: AshHarness.Reachability.graph()
@spec tool_list(module()) :: [{module(), atom(), AshHarness.Schema.Canonical.t()}]
```

## Resolving the actor

The harness resolves `identity.actor` at `new_session/2`:

```elixir
defp resolve_actor(actor_spec) do
  case actor_spec do
    fun when is_function(fun, 0) -> fun.()
    {mod, fun, args} -> apply(mod, fun, args)
    other -> other  # struct or map literal
  end
end
```

This lets agents be **multi-tenant**: a function-form actor can return
the current tenant's bot user, captured from process-dictionary or a
`Logger` metadata field set by the host app.

## Examples

### A read-only reporting agent

```elixir
defmodule Reports.SalesSummaryAgent do
  use AshHarness.Agent, domains: [MyApp.Sales]

  identity do
    name "Sales Summary"
    description "Read-only daily sales reporter."
    actor MyApp.Sales.system_reader()
  end

  scope do
    resource MyApp.Sales.Order do
      actions [:read, :by_date_range, :by_region]
    end
    resource MyApp.Sales.Refund do
      actions [:read]
    end
  end

  behavior do
    auto_execute [:read, :by_date_range, :by_region]
  end
end
```

No `confirm_before`, no `delegates_to`, default constraints. Smallest
viable agent.

### A delegation-heavy agent

```elixir
defmodule MyApp.Agents.SupervisorAgent do
  use AshHarness.Agent, domains: [MyApp.Tickets]

  identity do
    name "Supervisor"
    description "Routes work between specialist agents."
    actor MyApp.Agents.supervisor()
  end

  scope do
    resource MyApp.Tickets.Ticket do
      actions [:read]
    end
  end

  behavior do
    auto_execute [:read]
  end

  delegates_to do
    delegate MyApp.Agents.TriageAgent,    for: "newly opened tickets"
    delegate MyApp.Agents.IncidentAgent,  for: "tickets tagged as incidents"
    delegate MyApp.Agents.BillingAgent,   for: "tickets that touch billing or refunds"
  end

  constraints do
    max_mutations_per_turn 0    # supervisor doesn't mutate; only delegates
  end
end
```

## Open questions

- **Should `identity.model` be a list (e.g., `["anthropic:…", "openai:…"]`)
  for routing/fallback?** v0.1.0: single model. Multi-model routing is
  out of scope.
- **Should there be an agent-level `system_prompt_extras` for prose the
  user wants verbatim in the prompt?** Provisionally no — strategies
  cover this. Revisit if users push back.
- **How do we handle hot reloading?** When an agent module is recompiled
  during dev, the orchestrator's tool list must refresh. Likely
  `Code.ensure_loaded?` + recreate orchestrator on session start. Detail
  in `harness-runtime.md`.
