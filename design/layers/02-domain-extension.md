# Layer 02 — `AshHarness.Domain` extension

Adds optional domain-level agent metadata. Domains can define a domain
description and ubiquitous-language **terms** that all agents consuming
the domain inherit in their context.

## Purpose

Establishes shared vocabulary for a domain. The renderer prefixes the
"Vocabulary" section of the system prompt from this. Without it, agents
operate on a domain perfectly fine — but they don't get the
domain-specific term definitions that help them speak the language of
the business.

## DSL

```elixir
defmodule MyApp.Ticketing do
  use Ash.Domain,
    extensions: [AshHarness.Domain]

  resources do
    resource MyApp.Ticketing.Ticket
    resource MyApp.Ticketing.Project
    resource MyApp.Ticketing.Comment
  end

  agent_domain do
    description "Project management domain. Tracks work across projects and teams."

    term "ticket", "A discrete unit of work — a bug, feature request, or task."
    term "triage", "The process of assessing priority and assigning ownership."
    term "blocker", "A ticket whose resolution is required before other tickets can proceed."
  end
end
```

## Schema

```elixir
agent_domain do
  # Optional.
  description :: String.t()

  # Zero or more `term` entries.
  term word :: String.t(), definition :: String.t()
end
```

## Term entity

```elixir
defmodule AshHarness.Domain.Term do
  defstruct [:word, :definition]

  @type t :: %__MODULE__{word: String.t(), definition: String.t()}
end
```

## Introspection — `AshHarness.Domain.Info`

```elixir
@spec description(Ash.Domain.t()) :: String.t() | nil
def description(domain)

@spec terms(Ash.Domain.t()) :: [Term.t()]
def terms(domain)

@spec term_for(Ash.Domain.t(), String.t()) :: String.t() | nil
def term_for(domain, word)
```

## Compile-time validation (verifier)

| Check | Error |
| --- | --- |
| No duplicate term `word` within a domain | `"Duplicate term \"ticket\" defined in MyApp.Ticketing"` |
| Term word is non-empty | Spark schema validation |

## Aggregating across domains in a multi-domain agent

An agent declared with `domains: [A, B]` inherits the union of A's and B's
terms. **Conflict resolution:** if both A and B define a term with the
same `word`, the verifier on the *agent* (not the domain) raises:

```
Domain MyApp.Ticketing and MyApp.Billing both define the term "invoice".
Resolve the conflict by renaming one or by scoping the agent to a single domain.
```

This is a verifier on the agent module, not the domain — a single domain
shouldn't have to worry about other domains it might be combined with.

## Examples

### Minimal

```elixir
agent_domain do
  description "User accounts and authentication."
end
```

### Full

```elixir
agent_domain do
  description """
  Customer-facing e-commerce ordering. Covers orders, line items,
  shipments, and refunds. Does NOT cover: catalog, pricing, inventory.
  """

  term "order",     "A customer's intent to buy. Becomes a shipment after payment."
  term "shipment",  "Physical fulfillment of an order."
  term "refund",    "Returning money for a partially or fully cancelled order."
  term "RMA",       "Return Merchandise Authorization — a customer-initiated return flow."
end
```

## When *not* to use this extension

- The vocabulary is universal English; you don't need to define what
  "user" means.
- The domain is internal-only and the agent is internal-only; the
  resource descriptions on each resource carry enough.

There is no harm in skipping this extension. Resource-level annotations
remain the primary leverage; domain-level annotations are a force
multiplier when domain language matters.
