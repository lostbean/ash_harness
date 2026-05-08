# harness-runtime — Specification

## ADDED Requirements

### Requirement: Session lifecycle

`AshHarness.Harness.new_session/2` SHALL accept an agent module and
options, resolve the agent's identity actor (struct, function, or
MFA), render the initial context, assemble a `Jido.Composer.Orchestrator`
with the agent's skills plus a `DynamicAgentNode` for progressive
disclosure, and return an `%AshHarness.Harness.Session{}` struct.

#### Scenario: Session created with agent's actor
- **WHEN** `new_session/2` is called for an agent whose
  `identity.actor` is a 0-arity function
- **THEN** the function is invoked at session creation and the
  resolved value is stored in the session's `:actor` field

#### Scenario: Session uses agent's model when not overridden
- **WHEN** `new_session(MyAgent)` is called and the agent declared
  `model "anthropic:claude-sonnet-4-5"`
- **THEN** the resulting orchestrator uses that model string

#### Scenario: Session model can be overridden
- **WHEN** `new_session(MyAgent, model: "openai:gpt-4")` is called
- **THEN** the orchestrator uses the override, not the agent's
  declared model

### Requirement: Run a turn

`AshHarness.Harness.run/3` SHALL accept a session, a user message, and
options, send the message through the Jido orchestrator, and return
one of `{:ok, reply, session}`, `{:halt, %ApprovalRequest{}, session}`,
or `{:error, reason, session}`. The returned session SHALL carry the
updated trajectory, mutation count, and turn number.

#### Scenario: Successful turn returns reply
- **WHEN** the orchestrator completes a turn without suspension and
  without errors
- **THEN** `run/3` returns `{:ok, "<assistant text>", session}` and
  the session's trajectory contains an entry per executed action

#### Scenario: Confirmation halts the turn
- **WHEN** the orchestrator emits a tool call for an action listed in
  `confirm_before` and no prior approval exists
- **THEN** `run/3` returns `{:halt, %ApprovalRequest{}, session}` with
  the request describing the pending action

### Requirement: Resume a halted session

`AshHarness.Harness.resume/2` SHALL accept a halted session and an
`%ApprovalResponse{}` and continue execution. On `:approved`, the
gate pipeline SHALL re-enter at the budget gate; on `:rejected`, the
tool result SHALL convey the rejection back to the LLM as an error
string.

#### Scenario: Approved confirmation continues
- **WHEN** `resume/2` is called with `decision: :approved` for the
  pending request
- **THEN** the action proceeds through budget and policy gates,
  executes, and the session updates accordingly

#### Scenario: Rejected confirmation surfaces to LLM
- **WHEN** `resume/2` is called with `decision: :rejected`
- **THEN** the orchestrator receives an error tool result and the
  trajectory entry status is `:confirmation_rejected`

### Requirement: Scope gate

The harness SHALL refuse any tool dispatch where the (resource,
action) pair is not in the agent's scope. The refusal SHALL emit
`[:ash_harness, :scope, :violation]` telemetry and return an error
without invoking Ash.

#### Scenario: Out-of-scope action rejected
- **WHEN** an LLM emits a tool call for an action not in the agent's
  scope (e.g., via a stale tool reference or a malformed input)
- **THEN** the dispatch returns `{:error, :scope_violation, ...}` and
  Ash is not called

### Requirement: Reasoning gate

The harness SHALL refuse any mutating tool dispatch for an action in
`require_reasoning_for` when the input does not contain a non-empty
`reasoning` string. The refusal SHALL return an error and emit
`[:ash_harness, :reasoning, :missing]`.

#### Scenario: Reasoning required but missing
- **WHEN** the agent declares `require_reasoning_for [:assign]` and
  an `:assign` call arrives without `reasoning`
- **THEN** the dispatch returns `{:error, :reasoning_required, ...}`
  and Ash is not called

#### Scenario: Reasoning required and present
- **WHEN** the same call arrives with `reasoning: "..."`
- **THEN** the gate passes and execution continues

### Requirement: Confirmation gate

The harness SHALL halt any action listed in `confirm_before` until an
approval is received. The halt SHALL surface as a Jido
`%ApprovalRequest{}` with metadata containing the agent name, the
intended (resource, action), the input, and the reasoning (if any).

#### Scenario: Confirmation request metadata
- **WHEN** a confirmation halts a tool dispatch
- **THEN** the resulting `%ApprovalRequest{}` metadata contains the
  agent name, resource string, action atom, input map, and reasoning

### Requirement: Budget gate

The harness SHALL refuse any successful create / update / destroy /
mutating-generic action when the session's `mutation_count` already
equals the agent's `max_mutations_per_turn`. Reads SHALL NOT
contribute to the count. Failed actions SHALL NOT contribute. The
count SHALL increment only after successful execution.

#### Scenario: Read does not increment budget
- **WHEN** a read action executes successfully
- **THEN** `session.mutation_count` is unchanged

#### Scenario: Successful update increments budget
- **WHEN** an update action executes successfully
- **THEN** `session.mutation_count` increments by exactly one

#### Scenario: Budget exhausted
- **WHEN** `session.mutation_count == max_mutations_per_turn` and a
  mutating tool dispatches
- **THEN** the gate returns `{:error, :budget_exceeded, ...}` and Ash
  is not called

### Requirement: Policy gate

The harness SHALL call `Ash.can?(actor, action_input)` before
executing any mutating action. When `Ash.can?` returns `false`, the
gate SHALL refuse execution and return a `:policy_denied` error. When
`Ash.can?` returns `true` or `:maybe`, execution proceeds.

#### Scenario: Policy denies
- **WHEN** `Ash.can?` returns `false` for a tool dispatch
- **THEN** the gate emits `[:ash_harness, :policy, :denied]` and the
  dispatch returns an error

### Requirement: Action executor

`AshHarness.Harness.ActionExecutor.run/2` SHALL dispatch by Ash action
type: `:read` to `Ash.read/2`, `:create` to `Ash.create/2`, `:update`
to `Ash.update/2` (after loading the record by `id`), `:destroy` to
`Ash.destroy/2` (after loading by `id`), and `:action` to
`Ash.run_action/3`. The actor SHALL flow through every call.

#### Scenario: Update loads record before mutating
- **WHEN** an update tool is invoked with `id: "abc-123"` and other
  fields
- **THEN** the executor first calls `Ash.get!/3` for the record using
  the actor, then calls `Ash.update/2` on the loaded record

#### Scenario: Forbidden raises wrap to :policy_denied
- **WHEN** an Ash call raises `%Ash.Error.Forbidden{}`
- **THEN** the executor returns `{:error, {:policy_denied, error}}`

#### Scenario: Validation error wraps to :validation_failed
- **WHEN** an Ash call raises `%Ash.Error.Invalid{}`
- **THEN** the executor returns `{:error, {:validation_failed,
  error}}`

### Requirement: Trajectory entries

The harness SHALL append an `%AshHarness.Harness.TrajectoryEntry{}`
to the session for every gate outcome, every action execution, and
every confirmation. Entries SHALL include `:timestamp`,
`:turn_number`, `:intent`, `:result_status`, `:duration_ms`,
`:tokens_used`, `:repair_attempts`, and any caller-provided
`:metadata`.

#### Scenario: Trajectory captures denied call
- **WHEN** a tool dispatch is rejected by the scope gate
- **THEN** the session's trajectory contains an entry with
  `:result_status == :scope_violation`

### Requirement: Result struct

Every dispatch SHALL produce an `%AshHarness.Harness.Result{}` with
`:status`, `:intent`, `:data`, `:error`, `:changeset_errors`, and
`:duration_ms`. Status values SHALL be one of `:ok`, `:error`,
`:scope_violation`, `:reasoning_required`, `:confirmation_required`,
`:budget_exceeded`, `:policy_denied`.

#### Scenario: Successful result
- **WHEN** a tool executes successfully and returns a record
- **THEN** the result has `:status == :ok`, `:data` populated,
  `:error == nil`

#### Scenario: Validation failure result
- **WHEN** an Ash action returns a changeset with errors
- **THEN** the result has `:status == :error`,
  `:changeset_errors` populated as a list of `%{field: atom, message:
  string}` maps, and `:data == nil`
