defmodule AshHarness.Eval.Runner do
  @moduledoc """
  Runs scenarios from a module that uses `AshHarness.Eval`.

  For each scenario, the runner:

    1. Opens an `AshHarness.Eval.Sandbox` over the scenario's resources.
    2. Invokes the scenario's `setup`.
    3. Wraps the agent execution in `ReqCassette.with_cassette/3` so
       LLM traffic is recorded/replayed deterministically.
    4. Loops `Harness.run/3` and `Harness.resume/2` per the runner's
       `:auto_confirm` mode (default `:always_approve`), capped at
       `:max_turns` (default 12) before aborting with
       `:terminated_reason: :max_turns`.
    5. Reads final resource state into `ctx[:records]`, attaches the
       trajectory and session, then evaluates gates and reports.
    6. Closes the sandbox.

  Scenarios may opt out of cassette wrapping by declaring
  `agent(nil)` — those run gate/report logic against the explicit
  setup-provided state, which is useful for invariant-only scenarios
  that don't drive an LLM.

  ## Refreshing setup state

  Before evaluating gates, the runner walks the `setup_ctx` map returned
  by the scenario's `setup` block and refreshes each value:

    * **Ash structs with an `:id`** are re-read from the data layer via
      `Ash.get/3` so `gate :resource_state` sees post-run attribute
      values rather than the pre-run snapshot.
    * **`{:reload, module, id}` tuples** are explicit reload requests;
      the tuple is replaced by the freshly-loaded struct. Useful when
      the setup returns plain placeholder maps but you still want to
      pin the resource identity for the gate.
    * **Anything else** (plain maps, primitives, lists) passes through
      unchanged — the runner can't guess what resource a bare map
      belongs to.

  ## Options

    * `:auto_confirm` — `:always_approve` (default), `:always_reject`,
      or `{:custom, fn intent -> :approved | :rejected end}`.
    * `:max_turns` — int, defaults to 12.
    * `:cassette_module` — override the module used to resolve cassette
      paths; defaults to the scenario's caller.
    * `:req_options` — when provided, bypasses `ReqCassette.with_cassette/3`
      and passes these options straight through to
      `Harness.new_session/2`. Used by tests that want to inject an
      `LLMStub` plug without recording a cassette.
  """

  alias AshHarness.Eval.Cassette
  alias AshHarness.Eval.Gate
  alias AshHarness.Eval.Report
  alias AshHarness.Eval.Result
  alias AshHarness.Eval.Sandbox
  alias AshHarness.Eval.Scenario
  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Telemetry
  alias Jido.Composer.HITL.ApprovalResponse

  @default_max_turns 12

  @doc """
  Run a single `Scenario`. Returns an `Eval.Result`.
  """
  @spec run(Scenario.t(), keyword()) :: Result.t()
  def run(%Scenario{} = scenario, opts \\ []) do
    started_at = System.monotonic_time(:millisecond)

    Telemetry.emit(
      [:ash_harness, :eval, :scenario, :start],
      %{},
      %{scenario: scenario.name, agent: scenario.agent}
    )

    auto_confirm = resolve_auto_confirm(scenario, opts)
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)
    cassette_module = Keyword.get(opts, :cassette_module) || cassette_module_default(scenario)
    runner_req_options = Keyword.get(opts, :req_options)

    sandbox_resources = resources_for_sandbox(scenario)
    {:ok, sandbox} = Sandbox.open(sandbox_resources)

    setup_ctx =
      case scenario.setup do
        nil -> %{}
        f when is_function(f, 0) -> f.()
      end

    {trajectory, tokens, terminated_reason, session_after, terminated_error} =
      if scenario.agent && scenario.prompt do
        drive_agent(scenario, cassette_module, auto_confirm, max_turns, runner_req_options)
      else
        {[], 0, :not_executed, nil, nil}
      end

    records = refresh_records(setup_ctx)

    ctx = %{
      records: records,
      trajectory: trajectory,
      tokens_used: tokens,
      session: session_after
    }

    gate_results = Enum.map(scenario.gates, fn g -> evaluate_gate(g, ctx) end)
    report_results = Enum.map(scenario.reports, fn r -> evaluate_report(r, ctx) end)

    passed =
      Enum.all?(gate_results, fn %{checks: checks} ->
        Enum.all?(checks, fn {_label, ok?, _} -> ok? end)
      end)

    duration = System.monotonic_time(:millisecond) - started_at

    if session_after, do: Harness.terminate(session_after)
    :ok = Sandbox.close(sandbox)

    Telemetry.emit(
      [:ash_harness, :eval, :scenario, :stop],
      %{duration_ms: duration},
      %{scenario: scenario.name, passed: passed}
    )

    %Result{
      scenario_name: scenario.name,
      passed: passed,
      gate_results: gate_results,
      report_results: report_results,
      duration_ms: duration,
      tokens_used: tokens,
      session_trajectory: trajectory,
      terminated_reason: terminated_reason,
      terminated_error: terminated_error
    }
  end

  @doc """
  Run every scenario in an eval module.
  """
  @spec run_all(module(), keyword()) :: [Result.t()]
  def run_all(module, opts \\ []) when is_atom(module) do
    Enum.map(module.scenarios(), &run(&1, Keyword.put_new(opts, :cassette_module, module)))
  end

  # ----------------------------------------------------------------
  # Internal
  # ----------------------------------------------------------------

  defp drive_agent(%Scenario{} = scenario, _cassette_module, auto_confirm, max_turns, req_options)
       when is_list(req_options) do
    # Caller supplied their own req_options (e.g. an LLM stub plug);
    # skip cassette wrapping entirely.
    session = Harness.new_session(scenario.agent, req_options: req_options)
    loop(session, scenario.prompt, auto_confirm, max_turns, 0)
  rescue
    e -> {[], 0, :error, nil, e}
  end

  defp drive_agent(%Scenario{} = scenario, cassette_module, auto_confirm, max_turns, nil) do
    ensure_req_cassette!()

    cassette_path = Cassette.cassette_path(cassette_module, scenario.name)
    cassette_mode = Cassette.mode()

    cassette_opts = [
      mode: cassette_mode,
      dir: Path.dirname(cassette_path)
    ]

    cassette_name = Path.basename(cassette_path, ".json")

    # `apply/3` keeps the compiler from resolving `ReqCassette` at compile
    # time — important because `req_cassette` is declared
    # `only: [:dev, :test]` in mix.exs, so when ash_harness is compiled as
    # a path dependency of another package (e.g. the τ-bench child), the
    # module isn't visible at compile time even though the host typically
    # has its own req_cassette dep.
    apply(ReqCassette, :with_cassette, [
      cassette_name,
      cassette_opts,
      fn plug ->
        session =
          Harness.new_session(scenario.agent, req_options: [plug: plug])

        loop(session, scenario.prompt, auto_confirm, max_turns, 0)
      end
    ])
  rescue
    e -> {[], 0, :error, nil, e}
  end

  defp ensure_req_cassette! do
    unless Code.ensure_loaded?(ReqCassette) do
      Mix.raise("""
      AshHarness.Eval.Runner needs `:req_cassette` to drive scenarios.
      Add it to your `mix.exs` deps (it's already in ash_harness's deps
      under `only: [:dev, :test]`; if you're calling Eval.Runner from a
      child package, add `{:req_cassette, "~> 0.6"}` directly):

          defp deps do
            [
              {:req_cassette, "~> 0.6"}
            ]
          end
      """)
    end
  end

  defp loop(session, _prompt, _auto_confirm, max_turns, turn) when turn >= max_turns do
    trajectory = Harness.trajectory(session)
    {trajectory, 0, :max_turns, session, nil}
  end

  defp loop(%Session{} = session, prompt, auto_confirm, max_turns, turn) do
    case Harness.run(session, prompt) do
      {:ok, _reply, updated} ->
        {Harness.trajectory(updated), 0, :goal_met, updated, nil}

      {:halt, request, updated} ->
        decision = decide(auto_confirm, request)

        response = %ApprovalResponse{
          request_id: request_id(request),
          decision: decision,
          data: request_payload_data(request, updated.agent),
          responded_at: DateTime.utc_now()
        }

        case Harness.resume(updated, response) do
          {:ok, :resumed, resumed} ->
            # Fallback path: re-enter the loop with the same prompt.
            loop(resumed, prompt, auto_confirm, max_turns, turn + 1)

          {:ok, _reply, resumed} ->
            {Harness.trajectory(resumed), 0, :goal_met, resumed, nil}

          {:halt, _new_request, _} = halted_again ->
            handle_repeated_halt(halted_again, prompt, auto_confirm, max_turns, turn)

          {:error, reason, errored} ->
            {Harness.trajectory(errored), 0, :error, errored, reason}
        end

      {:error, reason, errored} ->
        {Harness.trajectory(errored), 0, :error, errored, reason}
    end
  end

  defp handle_repeated_halt({:halt, _new_request, resumed}, prompt, auto_confirm, max_turns, turn) do
    loop(resumed, prompt, auto_confirm, max_turns, turn + 1)
  end

  defp request_id(%{id: id}) when is_binary(id), do: id

  # Builds the `data` payload attached to the `ApprovalResponse`. The
  # session's `do_record_approval` keys `session.metadata.approvals`
  # under `{resource, action}`, and the secondary `ConfirmationGate`
  # looks the entry up by the same key — so the data **must** carry
  # `:resource` and `:action`.
  #
  # The orchestrator strategy's `ApprovalRequest.metadata` is
  # `%{tool_call_id, tool_name}` (see `Jido.Composer.ApprovalGate.partition_calls/3`).
  # Our own `ConfirmationGate.check/2` builds requests with
  # `metadata: %{resource, action, ...}`. Handle both shapes:
  #
  #   1. If the metadata already carries `:resource` and `:action`,
  #      pass them through.
  #   2. Otherwise, reverse-lookup `metadata.tool_name` against the
  #      agent's canonical tool list to recover `{resource, action}`.
  defp request_payload_data(%{metadata: %{} = m}, agent_module) do
    case Map.take(m, [:resource, :action]) do
      %{resource: _, action: _} = full ->
        full

      partial ->
        case lookup_tool(agent_module, Map.get(m, :tool_name) || Map.get(m, "tool_name")) do
          {:ok, %{resource: resource, action_name: action}} ->
            Map.merge(partial, %{resource: resource, action: action})

          :error ->
            partial
        end
    end
  end

  defp request_payload_data(_request, _agent_module), do: %{}

  defp lookup_tool(agent_module, tool_name)
       when is_atom(agent_module) and not is_nil(agent_module) and is_binary(tool_name) do
    case Enum.find(AshHarness.Agent.Info.tool_list(agent_module), fn c ->
           c.tool_name == tool_name
         end) do
      nil -> :error
      canonical -> {:ok, canonical}
    end
  rescue
    _ -> :error
  end

  defp lookup_tool(_, _), do: :error

  @doc false
  def decide(:always_approve, _), do: :approved
  def decide(:always_reject, _), do: :rejected

  def decide({:custom, fun}, request) when is_function(fun, 1) do
    case fun.(request) do
      :approved -> :approved
      :rejected -> :rejected
      _ -> :approved
    end
  end

  def decide(_, _), do: :approved

  @doc false
  # Re-reads every value in `setup_ctx` from the data layer where possible
  # and returns a map with the refreshed values. See the module doc's
  # "Refreshing setup state" section for the supported shapes.
  #
  # Public-but-`@doc false` so tests can exercise the contract directly
  # without spinning up a full eval scenario.
  @spec refresh_records(map() | term()) :: map() | term()
  def refresh_records(setup_ctx) when is_map(setup_ctx) do
    Enum.into(setup_ctx, %{}, fn {key, value} -> {key, refresh_record(value)} end)
  end

  def refresh_records(other), do: other

  defp refresh_record({:reload, mod, id}) when is_atom(mod) and not is_nil(id) do
    if ash_resource?(mod) do
      case Ash.get(mod, id, authorize?: false) do
        {:ok, fresh} -> fresh
        _ -> {:reload, mod, id}
      end
    else
      {:reload, mod, id}
    end
  rescue
    _ -> {:reload, mod, id}
  end

  defp refresh_record(%mod{id: id} = record) when is_atom(mod) and not is_nil(id) do
    if ash_resource?(mod) do
      case Ash.get(mod, id, authorize?: false) do
        {:ok, fresh} -> fresh
        _ -> record
      end
    else
      record
    end
  rescue
    _ -> record
  end

  defp refresh_record(value), do: value

  defp ash_resource?(mod) when is_atom(mod) do
    function_exported?(mod, :__ash_resource__, 0) or
      (Code.ensure_loaded?(Ash.Resource.Info) and
         Ash.Resource.Info.resource?(mod))
  end

  defp resources_for_sandbox(%Scenario{agent: nil}), do: []

  defp resources_for_sandbox(%Scenario{agent: agent_module}) do
    AshHarness.Agent.Info.scoped_resources(agent_module)
  rescue
    _ -> []
  end

  @doc false
  def resolve_auto_confirm(%Scenario{} = scenario, opts) do
    case Map.get(scenario, :auto_confirm) do
      nil -> Keyword.get(opts, :auto_confirm, :always_approve)
      mode -> mode
    end
  end

  defp cassette_module_default(%Scenario{agent: agent}) when is_atom(agent) and not is_nil(agent),
    do: agent

  defp cassette_module_default(_), do: AshHarness.Eval

  defp evaluate_gate(%Gate{kind: kind, check: fun}, ctx) do
    checks = fun.(ctx)

    Telemetry.emit(
      [:ash_harness, :eval, :gate, :checked],
      %{},
      %{kind: kind, checks: length(checks)}
    )

    %{kind: kind, checks: checks}
  end

  defp evaluate_report(%Report{kind: kind, compute: fun}, ctx) do
    computed = fun.(ctx)

    Telemetry.emit(
      [:ash_harness, :eval, :report, :computed],
      %{},
      %{kind: kind}
    )

    Map.put(computed, :kind, kind)
  end
end
