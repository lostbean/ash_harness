defmodule AshHarness.Harness.GeneratedAction do
  @moduledoc """
  Entry point that every generated `Jido.Action.run/2` callback
  delegates to. Runs the gate pipeline (Scope, Reasoning, Confirmation,
  Budget, Policy), invokes the action executor, and returns the
  `Jido.Action.run/2`-shaped result.

  Mutable per-turn state (mutation_count, trajectory, repair_attempts,
  approvals) flows through the `AshHarness.Harness.SessionAgent`
  GenServer reached via `ctx[:ash_harness_session_pid]`. Static
  `%Session{}` snapshots in `ctx[:ash_harness_session]` are honored as
  a fallback for tests that bypass the supervisor.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Harness.ActionExecutor
  alias AshHarness.Harness.BudgetGate
  alias AshHarness.Harness.ConfirmationGate
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.PolicyGate
  alias AshHarness.Harness.ReasoningGate
  alias AshHarness.Harness.Repair
  alias AshHarness.Harness.ScopeGate
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.TrajectoryEntry
  alias AshHarness.Telemetry

  @doc """
  Run one tool invocation through the harness pipeline.

  Returns a value shaped for `Jido.Action.run/2`:
    * `{:ok, result_map}` on success
    * `{:error, feedback_string}` on a refused or failed action
      (the LLM sees the string; the harness's trajectory captures
      the structured reason)
  """
  @spec dispatch(module(), module(), atom(), map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def dispatch(agent_module, resource, action_name, params, ctx) do
    pid = fetch_session_pid(ctx)
    session = fetch_session(ctx, agent_module, pid)
    started_at = System.monotonic_time(:millisecond)

    reasoning =
      Map.get(params, :_reasoning) ||
        Map.get(params, "_reasoning") ||
        Map.get(params, :reasoning) ||
        Map.get(params, "reasoning")

    intent = %Intent{
      resource: resource,
      action: action_name,
      input: strip_internal(params),
      reasoning: reasoning,
      request_id: Map.get(ctx, :request_id) || gen_request_id()
    }

    cap = AgentInfo.max_repair_loop_retries(agent_module)
    attempts = current_repair_attempts(pid, session, resource, action_name)

    if cap > 0 and attempts >= cap do
      handle_repair_exhausted(agent_module, intent, attempts, started_at, pid, session)
    else
      run_pipeline(agent_module, intent, session, pid, started_at)
    end
  end

  # ----------------------------------------------------------------
  # Pipeline
  # ----------------------------------------------------------------

  defp run_pipeline(agent_module, intent, session, pid, started_at) do
    with :ok <- scope_check(session, intent, pid, started_at),
         :ok <- reasoning_check(session, intent, pid, started_at),
         :ok <- confirmation_check(session, intent, pid, started_at),
         :ok <- budget_check(session, intent, pid, started_at),
         :ok <- policy_check(session, intent, pid, started_at) do
      execute(agent_module, intent, session, pid, started_at)
    end
  end

  defp scope_check(session, intent, pid, started_at) do
    case ScopeGate.check(session, intent) do
      :ok ->
        :ok

      {:error, reason} ->
        append(pid, intent, :scope_violation, started_at)
        emit_repair_feedback(session.agent, intent, reason)
        {:error, Repair.format_feedback(reason, intent)}
    end
  end

  defp reasoning_check(session, intent, pid, started_at) do
    case ReasoningGate.check(session, intent) do
      :ok ->
        :ok

      {:error, reason} ->
        append(pid, intent, :reasoning_required, started_at)
        # Reasoning-missing is retryable; charge an attempt.
        bump_repair_if_present(pid, intent)
        emit_repair_feedback(session.agent, intent, reason)
        {:error, Repair.format_feedback(reason, intent)}
    end
  end

  defp confirmation_check(session, intent, pid, started_at) do
    case ConfirmationGate.check(session, intent) do
      :ok ->
        :ok

      {:halt, request} ->
        append(pid, intent, :confirmation_required, started_at)
        {:error, "Confirmation required: #{request.prompt}"}
    end
  end

  defp budget_check(session, intent, pid, started_at) do
    case BudgetGate.check(session, intent) do
      :ok ->
        :ok

      {:error, reason} ->
        append(pid, intent, :budget_exceeded, started_at)
        emit_repair_feedback(session.agent, intent, reason)
        {:error, Repair.format_feedback(reason, intent)}
    end
  end

  defp policy_check(session, intent, pid, started_at) do
    case PolicyGate.check(session, intent) do
      :ok ->
        :ok

      {:error, reason} ->
        append(pid, intent, :policy_denied, started_at)
        emit_repair_feedback(session.agent, intent, reason)
        {:error, Repair.format_feedback(reason, intent)}
    end
  end

  defp execute(agent_module, intent, session, pid, started_at) do
    case ActionExecutor.run(session.actor, intent) do
      {:ok, result} ->
        emit_executed(agent_module, intent, :ok, started_at)

        if BudgetGate.mutating?(intent) do
          bump_mutation_if_present(pid)
        end

        append(pid, intent, :ok, started_at)
        {:ok, render_result(intent, result)}

      {:error, reason} ->
        status = result_status_for_error(reason)
        emit_executed(agent_module, intent, :error, started_at)
        emit_repair_feedback(agent_module, intent, reason)

        if Repair.retryable?(reason) do
          bump_repair_if_present(pid, intent)
        end

        append(pid, intent, status, started_at)
        {:error, Repair.format_feedback(reason, intent)}
    end
  end

  defp handle_repair_exhausted(agent_module, intent, attempts, started_at, pid, _session) do
    Telemetry.emit(
      [:ash_harness, :repair, :exhausted],
      %{attempts: attempts},
      %{
        agent: agent_module,
        resource: intent.resource,
        action: intent.action,
        request_id: intent.request_id
      }
    )

    append(pid, intent, :repair_exhausted, started_at)

    {:error, Repair.format_feedback(:repair_exhausted, intent)}
  end

  # ----------------------------------------------------------------
  # SessionAgent helpers
  # ----------------------------------------------------------------

  defp fetch_session_pid(ctx) do
    case Map.get(ctx, :ash_harness_session_pid) do
      pid when is_pid(pid) ->
        if Process.alive?(pid), do: pid, else: nil

      _ ->
        nil
    end
  end

  defp fetch_session(ctx, agent_module, pid) when is_pid(pid) do
    case SessionAgent.get_state(pid) do
      %Session{} = s -> s
      _ -> fallback_session(ctx, agent_module)
    end
  end

  defp fetch_session(ctx, agent_module, _pid), do: fallback_session(ctx, agent_module)

  defp fallback_session(ctx, agent_module) do
    case Map.get(ctx, :ash_harness_session) do
      %Session{} = s -> s
      _ -> %Session{agent: agent_module, actor: nil, request_id: gen_request_id()}
    end
  end

  defp current_repair_attempts(pid, _session, resource, action) when is_pid(pid) do
    SessionAgent.repair_attempts(pid, {resource, action})
  end

  defp current_repair_attempts(_pid, %Session{repair_attempts: ra}, resource, action) do
    Map.get(ra || %{}, {resource, action}, 0)
  end

  defp bump_mutation_if_present(pid) when is_pid(pid), do: SessionAgent.bump_mutation(pid)
  defp bump_mutation_if_present(_), do: :ok

  defp bump_repair_if_present(pid, %Intent{resource: r, action: a}) when is_pid(pid),
    do: SessionAgent.bump_repair_attempt(pid, {r, a})

  defp bump_repair_if_present(_, _), do: :ok

  defp append(pid, intent, status, started_at) when is_pid(pid) do
    duration = System.monotonic_time(:millisecond) - started_at
    SessionAgent.append_trajectory(pid, entry(intent, status, duration, pid))
  end

  defp append(_pid, _intent, _status, _started_at), do: :ok

  defp entry(intent, status, duration, pid) do
    turn =
      case SessionAgent.get_state(pid) do
        %Session{turn_number: t} -> t
        _ -> 0
      end

    %TrajectoryEntry{
      timestamp: DateTime.utc_now(),
      turn_number: turn,
      intent: intent,
      result_status: status,
      duration_ms: duration,
      tokens_used: nil,
      repair_attempts: nil,
      metadata: %{request_id: intent.request_id}
    }
  end

  defp result_status_for_error({:validation_failed, _}), do: :validation_failed
  defp result_status_for_error(%Ash.Error.Invalid{}), do: :validation_failed
  defp result_status_for_error({:policy_denied, _}), do: :policy_denied
  defp result_status_for_error(%Ash.Error.Forbidden{}), do: :policy_denied
  defp result_status_for_error(_), do: :error

  defp emit_executed(agent_module, intent, status, started_at) do
    duration = System.monotonic_time(:millisecond) - started_at

    Telemetry.emit(
      [:ash_harness, :action, :executed],
      %{duration_ms: duration},
      %{
        agent: agent_module,
        resource: intent.resource,
        action: intent.action,
        status: status,
        request_id: intent.request_id
      }
    )
  end

  defp emit_repair_feedback(agent_module, intent, reason) do
    Telemetry.emit(
      [:ash_harness, :repair, :feedback],
      %{attempt: 1},
      %{
        agent: agent_module,
        resource: intent.resource,
        action: intent.action,
        reason_class: reason_class(reason),
        request_id: intent.request_id
      }
    )
  end

  defp reason_class({:validation_failed, _}), do: :validation
  defp reason_class(%Ash.Error.Invalid{}), do: :validation
  defp reason_class({:policy_denied, _}), do: :policy
  defp reason_class(%Ash.Error.Forbidden{}), do: :policy
  defp reason_class(reason) when is_atom(reason), do: reason
  defp reason_class(_), do: :unknown

  defp strip_internal(params) when is_map(params) do
    params
    |> Map.delete(:_reasoning)
    |> Map.delete("_reasoning")
  end

  defp gen_request_id,
    do: "req_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)

  defp render_result(%Intent{action: _}, records) when is_list(records) do
    %{count: length(records), records: Enum.map(records, &sanitize/1)}
  end

  defp render_result(%Intent{}, %{destroyed: true} = result), do: result
  defp render_result(%Intent{}, record) when is_struct(record), do: %{record: sanitize(record)}
  defp render_result(%Intent{}, result), do: %{result: sanitize(result)}

  # ----------------------------------------------------------------
  # Sanitization
  #
  # Converts action results into JSON-safe shapes before handing them
  # back to Jido / the LLM. Ash resource structs become plain maps of
  # their public attributes; `Ash.NotLoaded` becomes `nil`; `Decimal`
  # and date/time types become ISO-8601 strings; `MapSet` becomes a
  # list. The LLM doesn't need Ash internals, and these types don't
  # derive `Jason.Encoder`.
  # ----------------------------------------------------------------

  defp sanitize(%Ash.NotLoaded{}), do: nil
  defp sanitize(%Decimal{} = d), do: Decimal.to_string(d)
  defp sanitize(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp sanitize(%Date{} = d), do: Date.to_iso8601(d)
  defp sanitize(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  defp sanitize(%Time{} = t), do: Time.to_iso8601(t)
  defp sanitize(%MapSet{} = ms), do: ms |> MapSet.to_list() |> Enum.map(&sanitize/1)

  defp sanitize(%_mod{__meta__: _} = struct) do
    # Ash/Ecto resource struct — flatten to a plain map of public
    # attributes only, recursing into each value so relationships that
    # are `Ash.NotLoaded` become `nil`.
    struct
    |> ash_record_to_map()
    |> sanitize_map()
  end

  defp sanitize(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> sanitize_map()
  end

  defp sanitize(list) when is_list(list), do: Enum.map(list, &sanitize/1)
  defp sanitize(map) when is_map(map), do: sanitize_map(map)
  defp sanitize(other), do: other

  defp sanitize_map(map) do
    map
    |> Map.drop([:__meta__, :__struct__])
    |> Enum.into(%{}, fn {k, v} -> {k, sanitize(v)} end)
  end

  defp ash_record_to_map(%mod{} = record) do
    if function_exported?(Ash.Resource.Info, :public_attributes, 1) do
      attrs =
        mod
        |> Ash.Resource.Info.public_attributes()
        |> Enum.map(& &1.name)

      base =
        Enum.into(attrs, %{id: Map.get(record, :id)}, fn name ->
          {name, Map.get(record, name)}
        end)

      base
    else
      record
      |> Map.from_struct()
      |> Map.drop([:__meta__])
    end
  end
end
