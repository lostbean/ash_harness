# delegation — Specification

## ADDED Requirements

### Requirement: Delegation initiation

`AshHarness.Delegation.initiate/4` SHALL accept the caller's session,
a target agent module, a question string, and options, and SHALL
return one of `{:ok, reply, updated_caller_session,
target_trajectory}`, `{:error, :delegation_not_permitted}`, `{:error,
:delegation_depth_exceeded}`, or `{:error, term()}`.

#### Scenario: Permitted delegation succeeds
- **WHEN** Agent A calls `initiate/4` for Agent B and B is in A's
  `delegates_to` list
- **THEN** a fresh B session runs the question and returns its text
  reply; A's session trajectory contains a delegation entry

#### Scenario: Unpermitted delegation rejected
- **WHEN** A calls `initiate/4` for Agent B where B is NOT in A's
  `delegates_to` list
- **THEN** the call returns `{:error, :delegation_not_permitted}` and
  no B session is created

### Requirement: Anti-corruption boundary

The delegate's reply SHALL be a string. The caller SHALL NOT receive
the delegate's records, structured data, raw query results, or
delegate's conversation history. Each agent SHALL use its own
`identity.actor`; the caller's actor SHALL NOT be propagated to the
delegate.

#### Scenario: Reply is a string
- **WHEN** B answers "Customer X is in good standing"
- **THEN** A receives only the string `"Customer X is in good
  standing"` and no Ash record references

#### Scenario: Delegate uses its own actor
- **WHEN** A's actor differs from B's identity actor
- **THEN** during B's execution, B's actor (not A's) flows into
  `Ash.can?` and Ash calls

### Requirement: Delegation depth limit

The library SHALL track delegation depth per chain. The default cap
SHALL be 3, configurable via `config :ash_harness,
:delegation_max_depth`. When exceeded, `initiate/4` SHALL return
`{:error, :delegation_depth_exceeded}`.

#### Scenario: Depth exceeded
- **WHEN** A→B→C→D→E is attempted and the cap is 3
- **THEN** the fourth call returns `{:error,
  :delegation_depth_exceeded}` and emits
  `[:ash_harness, :delegation, :denied]` with reason
  `:depth_exceeded`

### Requirement: Independent mutation counts

Each agent's session SHALL have its own `mutation_count`. A
delegate's mutations SHALL NOT count against the caller's budget;
the caller's mutations SHALL NOT affect the delegate's budget.

#### Scenario: Delegate's mutations isolated
- **WHEN** B performs three mutations during a delegation
- **THEN** A's `mutation_count` is unchanged and only B's session
  reflects those three mutations

### Requirement: Trajectory observability

The caller's trajectory SHALL contain a delegation entry recording
the target agent, the question, and a reference to the delegate's
trajectory. The delegate's full trajectory SHALL be returned from
`initiate/4` for observability and eval, but it SHALL NOT be exposed
to the calling LLM as context.

#### Scenario: Delegation entry contains target name
- **WHEN** A delegates to B
- **THEN** A's trajectory has one entry with `intent.type ==
  :delegation` and `intent.target == B`
