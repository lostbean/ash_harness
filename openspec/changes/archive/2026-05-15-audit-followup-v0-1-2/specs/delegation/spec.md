# delegation — Specification (v0.1.2 deltas)

## ADDED Requirements

### Requirement: Delegation skill exposed to the LLM

The library SHALL add a single dynamic `delegate(target, question)`
tool to the orchestrator node list of each agent module whose
`delegates_to` is non-empty. The tool SHALL accept `target: string`
(matched case-insensitively against the agent's declared delegate
names) and `question: string`, and SHALL dispatch through
`AshHarness.Delegation.initiate/4`. The tool SHALL NOT be gated by
`requires_approval`. When the agent has an empty `delegates_to`, no
delegation tool SHALL be added.

#### Scenario: Tool is present when delegates_to is non-empty
- **WHEN** an agent with `delegates_to [{MyApp.BillingAgent, ...}]`
  compiles
- **THEN** its orchestrator's `tool_nodes/0` contains a node for
  `AshHarness.Delegation.Skill` and the node is not flagged
  `requires_approval`

#### Scenario: Tool is absent when delegates_to is empty
- **WHEN** an agent with no `delegates_to` block compiles
- **THEN** its orchestrator's `tool_nodes/0` does NOT contain the
  delegation node

#### Scenario: Tool dispatches through initiate
- **WHEN** the LLM calls `delegate(target: "billing", question: "...")`
- **THEN** the action invokes `AshHarness.Delegation.initiate/4` with
  the matched agent module and the question; the reply string from
  the delegate is returned to the LLM as a tool result

#### Scenario: Target name does not resolve
- **WHEN** the LLM calls `delegate(target: "unknown", question: "...")`
- **THEN** the tool returns an error result describing the available
  target names; `initiate/4` is not called

### Requirement: Delegation trajectory entry carries reply payload

Delegation trajectory entries SHALL carry a `:data` map containing
`:reply_text` (the delegate's string reply) and
`:target_trajectory_id` (a binary id that can be used to look up the
delegate's full trajectory in observability tooling).
`:target_trajectory_id` SHALL be generated at delegation start and
SHALL also appear in the `[:ash_harness, :delegation, :started]` and
`:ended` telemetry metadata.

#### Scenario: Entry contains reply text
- **WHEN** A delegates to B and B replies "ok"
- **THEN** A's trajectory contains exactly one delegation entry whose
  `data.reply_text == "ok"`

#### Scenario: Trajectory id correlates telemetry to entry
- **WHEN** A delegates to B
- **THEN** the `:started` and `:ended` telemetry events for that
  delegation carry the same `target_trajectory_id` value that appears
  in the trajectory entry's `data.target_trajectory_id`

### Requirement: Delegation initiation

`AshHarness.Delegation.initiate/4` SHALL accept the caller's session,
a target agent module, a question string, and options, and SHALL
return one of:

- `{:ok, reply, updated_caller_session, target_trajectory}` on success
- `{:error, %AshHarness.Errors.DelegationNotPermitted{from, to, reason}}`
  when the target is not in the caller's `delegates_to` list
- `{:error, %AshHarness.Errors.DelegationDepthExceeded{from, to, depth,
  max_depth}}` when the delegation depth cap is exceeded
- `{:error, :delegate_halted}` when the child session suspended on its
  own HITL (an internal atom — the LLM-facing skill translates this to
  `{:error, "delegate halted: requires confirmation"}` so the parent
  agent's LLM sees text, never an atom)
- `{:error, term()}` for any other downstream failure

The function SHALL live in `AshHarness.Delegation.Initiate` and be
re-exported from `AshHarness.Delegation` for backward compatibility.

#### Scenario: Permitted delegation succeeds
- **WHEN** Agent A calls `initiate/4` for Agent B and B is in A's
  `delegates_to` list
- **THEN** a fresh B session runs the question and returns its text
  reply; A's session trajectory contains a delegation entry with the
  reply payload under `data.reply_text`

#### Scenario: Unpermitted delegation rejected with struct
- **WHEN** A calls `initiate/4` for Agent B where B is NOT in A's
  `delegates_to` list
- **THEN** the call returns `{:error,
  %AshHarness.Errors.DelegationNotPermitted{from: A, to: B}}` and no
  B session is created

#### Scenario: Delegation depth exceeded returns struct
- **WHEN** A calls `initiate/4` and the running depth equals
  `max_depth`
- **THEN** the call returns `{:error,
  %AshHarness.Errors.DelegationDepthExceeded{from: A, to: B, depth: n,
  max_depth: max}}` and no further B session is created

#### Scenario: Skill translates child-halt to text error
- **WHEN** the child agent suspends on its own ApprovalRequest during
  a delegation call
- **THEN** `Initiate.run/4` returns `{:error, :delegate_halted}` and
  `AshHarness.Delegation.Skill` translates that atom into
  `{:error, "delegate halted: requires confirmation"}` for the LLM
  tool result. Nested HITL is deferred — the child's suspension stays
  on the child; the parent agent does not see an ApprovalRequest.
