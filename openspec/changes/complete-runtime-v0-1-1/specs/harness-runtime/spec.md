# harness-runtime — Specification (v0.1.1 deltas)

## MODIFIED Requirements

### Requirement: Session lifecycle

`AshHarness.Harness.new_session/2` SHALL accept an agent module and
options, resolve the agent's identity actor (struct, function, or
MFA), render the initial context, **start a supervised
`AshHarness.Harness.SessionAgent` GenServer holding the mutable
session parts (mutation_count, trajectory, repair_attempts,
approvals)**, assemble the agent's orchestrator with `confirm_before`
nodes flagged `requires_approval: true`, and return a
`%AshHarness.Harness.Session{}` snapshot whose `:metadata` includes
the GenServer pid under the key `:session_pid`.

#### Scenario: SessionAgent pid is reachable from the session struct
- **WHEN** `new_session/2` returns a session
- **THEN** `session.metadata.session_pid` is a live pid that responds
  to `AshHarness.Harness.SessionAgent.get_state/1`

#### Scenario: Session is supervised
- **WHEN** the SessionAgent crashes mid-turn
- **THEN** the `AshHarness.Harness.SessionSupervisor` does not restart
  it (transient restart strategy); the host's next `run/3` returns
  `{:error, :session_terminated, session}`

### Requirement: Budget gate increments on success

The harness SHALL increment `session.mutation_count` after a
successful `:create`, `:update`, `:destroy`, or mutating generic
action. Reads SHALL NOT increment; failed mutations SHALL NOT
increment. The increment SHALL be observable via
`Harness.mutation_count/1` on the session returned from `run/3`.

#### Scenario: Successful update bumps the counter
- **WHEN** a successful update action returns from `Harness.run/3`
- **THEN** `Harness.mutation_count(session)` is one greater than before
  the turn

#### Scenario: Failed mutation does not bump
- **WHEN** a `:create` action returns a validation error
- **THEN** `Harness.mutation_count(session)` is unchanged

### Requirement: Trajectory entries are appended during dispatch

The harness SHALL append a `%AshHarness.Harness.TrajectoryEntry{}` to
the session's trajectory for every gate refusal and every executed
action. Entries SHALL include `:timestamp`, `:turn_number`, `:intent`,
`:result_status`, and `:duration_ms`. After `run/3` returns, the
session's trajectory SHALL reflect the full per-tool-call sequence.

#### Scenario: Refused scope dispatch is recorded
- **WHEN** an LLM emits a tool call refused by `ScopeGate`
- **THEN** `Harness.trajectory(session)` contains an entry with
  `:result_status == :scope_violation`

#### Scenario: Successful action is recorded
- **WHEN** a `:read` action returns successfully
- **THEN** the trajectory contains an entry with `:result_status == :ok`
  and a populated `:duration_ms`

### Requirement: Confirmation resume continues the suspended flow

`Harness.resume/2` SHALL accept a halted session and an
`%ApprovalResponse{}`, hand the response to the underlying Jido
orchestrator's suspension/resume API, and return one of `{:ok, reply,
session}`, `{:halt, request, session}`, or `{:error, reason, session}`
without requiring the host to re-call `run/3` with the original
prompt. On `:rejected`, the next tool result conveyed to the LLM
SHALL describe the rejection (e.g., "Human rejected the requested
action.").

#### Scenario: Approved resume continues the turn
- **WHEN** `resume/2` is called with `decision: :approved` for the
  pending request
- **THEN** the orchestrator continues from the suspension point; the
  approved action executes; `run/3`-shaped result is returned

#### Scenario: Rejected resume surfaces to the LLM
- **WHEN** `resume/2` is called with `decision: :rejected`
- **THEN** the orchestrator continues with an error tool result for
  the pending call; the trajectory entry has
  `:result_status == :confirmation_rejected`

### Requirement: Confirmation halts originate at the orchestrator strategy

For each agent module that uses `AshHarness.Agent`, the library SHALL
generate at compile time a `<MyAgent>.Orchestrator` module that uses
`Jido.Composer.Orchestrator` and lists each scoped tool node with the
correct `requires_approval` flag derived from the agent's
`behavior.confirm_before` list. `Harness.new_session/2` SHALL
instantiate this generated orchestrator instead of calling
`Jido.Composer.Skill.assemble/2`.

#### Scenario: Generated orchestrator exists
- **WHEN** an agent compiles
- **THEN** `<MyAgent>.Orchestrator` is a loaded module that
  `use Jido.Composer.Orchestrator`

#### Scenario: confirm_before action halts via strategy
- **WHEN** an LLM emits a tool call for an action listed in
  `confirm_before`, with no prior approval
- **THEN** the orchestrator's `query_sync/3` returns
  `{:suspended, agent, suspension}` carrying the agent's
  `%ApprovalRequest{}`
