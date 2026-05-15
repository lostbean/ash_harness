# domain-annotations — Specification

## ADDED Requirements

### Requirement: Domain annotation DSL

The `AshHarness.Domain` Spark DSL extension SHALL provide an
`agent_domain` section on Ash domains with: an optional `description`
(string) and zero or more `term` entities of `(word :: String,
definition :: String)`.

#### Scenario: Domain declares description and terms
- **WHEN** a domain uses `extensions: [AshHarness.Domain]` and declares
  `agent_domain do description "..." ; term "x", "..." end`
- **THEN** compilation succeeds and the domain exposes the description
  and the term list via introspection

#### Scenario: Domain has no annotations
- **WHEN** a domain does not use the `AshHarness.Domain` extension or
  omits the `agent_domain` block
- **THEN** `AshHarness.Domain.Info.description/1` returns `nil` and
  `AshHarness.Domain.Info.terms/1` returns `[]`

### Requirement: Domain annotation introspection

The `AshHarness.Domain.Info` module SHALL expose `description/1`,
`terms/1`, and `term_for/2`. All functions SHALL accept either a domain
module or a Spark DSL state.

#### Scenario: Lookup a term by word
- **WHEN** `AshHarness.Domain.Info.term_for(MyDomain, "ticket")` is
  called and a term with `word: "ticket"` is declared
- **THEN** the term's `definition` field is returned as a string

### Requirement: Domain term uniqueness

A domain SHALL NOT declare two terms with the same `word`. The
extension's verifier SHALL refuse to compile a domain that violates
this rule.

#### Scenario: Duplicate term within a domain
- **WHEN** a domain declares `term "x", "first"` and `term "x",
  "second"` in the same `agent_domain` block
- **THEN** compilation fails with a message naming the duplicate word
  and the domain module

### Requirement: Term entity struct

The library SHALL provide an `AshHarness.Domain.Term` struct with
fields `:word` (string) and `:definition` (string), used as the target
type for parsed term entities and returned by introspection.

#### Scenario: Inspect a term
- **WHEN** `AshHarness.Domain.Info.terms(MyDomain)` returns terms
- **THEN** each element is a `%AshHarness.Domain.Term{word: String.t(),
  definition: String.t()}` struct
