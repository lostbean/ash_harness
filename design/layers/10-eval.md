# Layer 10 — Eval Framework

Three-layer evaluation: **deterministic state assertions are gates**;
trajectory metrics and qualitative scores are diagnostics. Decision
recorded in ADR 0002.

## Why gate, not weighted average

The original spec proposed a composite weighted score (deterministic .5,
trajectory .3, qualitative .2). Research strongly suggests this is
out-of-step with current practice (Braintrust, Inspect AI, Anthropic
internal guidance). The failure mode is straightforward: a high
qualitative score papers over a deterministic failure. For agents that
take real actions on real data, that is exactly the failure mode you
cannot tolerate.

So:

- **`gate`** blocks must pass for the scenario to pass. They are
  binary.
- **`report`** blocks are observed and surfaced in the run output, but
  they do not affect pass/fail.

## DSL

```elixir
defmodule MyApp.Evals.TriageEval do
  use AshHarness.Eval

  scenario "assigns critical ticket to least-loaded engineer" do
    agent MyApp.Agents.TriageAgent

    setup do
      ticket = create!(Ticket, title: "Prod down", priority: :critical)
      _alice = create!(Member, name: "Alice", workload: :light)
      _bob   = create!(Member, name: "Bob", workload: :heavy)
      %{ticket: ticket}
    end

    prompt "Triage this incoming critical ticket"

    # Gate (must pass)
    gate :resource_state do
      assert :status,      &(&1 == :in_progress)
      assert :assigned_to, &(&1 != nil)
    end

    # Diagnostic
    report :trajectory do
      max_actions 8
      max_tokens  15_000
      includes_sequence [
        {:read,   Member, :by_workload},
        {:update, Ticket, :assign}
      ]
      excludes [
        {:destroy, Ticket, :destroy}
      ]
    end

    # Diagnostic
    report :qualitative do
      criterion :reasoning, threshold: 3.5
      criterion :action_efficiency, threshold: 4.0
    end
  end
end
```

## Section semantics

### `setup`

A 0-arity block. Returns a map of named entities bound for use in
gates/reports. Runs in a test transaction (or ETS sandbox) that's
reverted at scenario end.

### `prompt`

The user message that kicks off the agent.

### `gate :resource_state`

Asserts post-state of resources. Each `assert` matches a record by
name (from setup) and applies a function to a field. **All gates must
pass for scenario to pass.** If any assertion fails, the scenario fails
with a structured error explaining which assertion failed.

Multiple `gate` blocks may exist (e.g., one per resource), all must
pass.

### `report :trajectory`

Trajectory checks against the session's trajectory log:

- `max_actions N` — total action count.
- `max_tokens N` — sum of tokens across the run.
- `includes_sequence [{type, resource, action}, …]` — the listed
  actions appear in this order somewhere in the trajectory.
- `excludes [{type, resource, action}, …]` — none of the listed
  actions appear at all.

Each check produces a `%TrajectoryReport{name, expected, actual,
passed}` in the result. Failed checks are surfaced; they do **not** fail
the scenario.

### `report :qualitative`

LLM-as-judge scoring. Each `criterion` runs the judge model with a
rubric prompt asking for a 0–5 score on a specific dimension. The
threshold is the value above which the criterion is considered
"passing" *for reporting purposes only* — never gates pass/fail.

Built-in criteria:

- `:reasoning` — does the agent explain its decisions?
- `:action_efficiency` — did the agent take the most direct path?
- `:tool_use_quality` — were tools used correctly (right tool for the
  job)?

Custom criteria:

```elixir
report :qualitative do
  criterion :tone,
    prompt: """
    Score 0-5 how professional and customer-friendly the agent's
    final reply is.
    """,
    threshold: 4.0
end
```

The judge model is configured separately from the agent's model
(different family, different vendor preferred — see ADR 0002 on
self-preference bias).

## Scenario struct

```elixir
defmodule AshHarness.Eval.Scenario do
  defstruct [
    :name,
    :agent_module,
    :setup_fn,
    :prompt,
    :gates,             # [%Gate{}]
    :reports,           # [%Report{}]
    :metadata
  ]
end

defmodule AshHarness.Eval.Gate do
  @type t :: %__MODULE__{
    kind: :resource_state | :invariant,
    spec: any()
  }
  defstruct [:kind, :spec]
end

defmodule AshHarness.Eval.Report do
  @type t :: %__MODULE__{
    kind: :trajectory | :qualitative,
    spec: any()
  }
  defstruct [:kind, :spec]
end
```

## Result struct

```elixir
defmodule AshHarness.Eval.Result do
  defstruct [
    :scenario_name,
    :passed,            # boolean — true iff all gates passed
    :gate_results,      # [%GateResult{passed, kind, details}]
    :report_results,    # [%ReportResult{kind, observations}]
    :duration_ms,
    :tokens_used,
    :session_trajectory # for debugging
  ]
end
```

## Runner

```elixir
defmodule AshHarness.Eval.Runner do
  @spec run(scenario :: %Scenario{}, opts :: keyword()) :: %Result{}
  def run(scenario, opts \\ [])
  # Steps:
  # 1. Run setup_fn (binding entities).
  # 2. Build session via AshHarness.Harness.new_session(scenario.agent_module).
  # 3. Run AshHarness.Harness.run(session, scenario.prompt).
  # 4. Continue resume() loop (auto-approve confirmation prompts via
  #    a test policy).
  # 5. Run all gates against current resource state. Aggregate pass/fail.
  # 6. Run all reports against trajectory + final session state.
  #    Trajectory: deterministic checks.
  #    Qualitative: judge model calls (parallel where independent).
  # 7. Build %Result{} and return.

  @spec run_all(eval_module :: module(), keyword()) :: [%Result{}]
  def run_all(eval_module, opts \\ [])
end
```

## Test isolation

Scenarios run in:

- **ETS sandbox** for ETS-backed resources (each scenario has its own
  ETS table or reset between scenarios).
- **DB transaction** for AshPostgres-backed resources (rollback at
  scenario end).
- A configured `Mox`-style stub for any external services the agent's
  resources call.

The eval framework configures `Ash` to use the test data layer for the
duration of the scenario. Host apps can opt in/out via a config flag.

## Confirmations during eval

Eval scenarios auto-approve confirmation requests by default (so the
trajectory completes). To exercise the rejection path, set
`auto_confirm: :always_reject` on the scenario or use a custom
`confirm_with: fn intent -> :approved | :rejected end` callback.

## Judge configuration

```elixir
config :ash_harness, :eval,
  judge_model: "anthropic:claude-opus-4-7",
  judge_provider_options: [],
  default_threshold: 3.5
```

The judge runs through Jido as a normal agent (no tools, just structured
output), giving us free observability and prompt caching for repeated
scenario runs.

## Open questions

- **Pairwise vs pointwise qualitative scoring?** v0.1.0: pointwise
  (simpler). v0.2 may add pairwise comparison for regression testing.
- **Trajectory "includes_sequence" — strict order or just inclusion?**
  v0.1.0: ordered subsequence (each item must appear, in this order,
  but with arbitrary other actions between). Configurable.
- **Resource-state gates with relations:** `assert :ticket.assigned_to,
  &(&1.workload == :light)` — defer to v0.2; v0.1.0 is flat fields only.
- **Failure messages:** make them paste-able into a follow-up prompt
  for debugging? Add `--rerun-from-failure` to mix tasks? v0.2.
