defmodule AshHarness.Harness do
  @moduledoc """
  Runtime entry point for AshHarness. Builds sessions, runs turns,
  resumes from confirmation halts, and exposes the trajectory.

  The actual LLM loop is driven by `jido_composer`. The harness owns
  the gate pipeline (scope, reasoning, confirmation, budget, policy)
  and the Ash dispatch — that logic runs inside the generated
  `Jido.Action.run/2`, which delegates to
  `AshHarness.Harness.GeneratedAction.dispatch/5`.

  Mutable per-turn state — `mutation_count`, `trajectory`,
  `repair_attempts`, recorded `approvals` — lives in a supervised
  `AshHarness.Harness.SessionAgent` GenServer. The `%Session{}` struct
  returned to host code is a snapshot at turn boundaries; the agent
  pid is carried inside `session.metadata.session_pid`.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.ContextRenderer
  alias AshHarness.Harness.Intent
  alias AshHarness.Harness.OrchestratorFactory
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent
  alias AshHarness.Harness.SessionSupervisor
  alias AshHarness.Harness.TrajectoryEntry
  alias Jido.Composer.HITL.ApprovalRequest
  alias Jido.Composer.HITL.ApprovalResponse
  alias Jido.Composer.Suspension

  @doc """
  Build a fresh `%Session{}` for the given agent module.

  ## Options
    * `:actor` — override the agent's identity actor
    * `:model` — override the agent's declared model
    * `:metadata` — host-app metadata map
    * `:request_id` — host-supplied request id (else generated)
  """
  @spec new_session(module(), keyword()) :: Session.t()
  def new_session(agent_module, opts \\ []) when is_atom(agent_module) do
    actor = Keyword.get(opts, :actor) || resolve_actor(AgentInfo.actor(agent_module))
    model = Keyword.get(opts, :model) || AgentInfo.model(agent_module)
    metadata = Keyword.get(opts, :metadata, %{})
    request_id = Keyword.get(opts, :request_id) || gen_request_id()

    rendered = ContextRenderer.render(agent_module, actor: actor)

    base_session = %Session{
      agent: agent_module,
      actor: actor,
      model: model,
      rendered_context: rendered,
      request_id: request_id,
      metadata: metadata,
      options: Keyword.drop(opts, [:actor, :model, :metadata, :request_id])
    }

    session_with_orch =
      case OrchestratorFactory.build(base_session) do
        {:ok, jido_agent} -> %{base_session | jido_orchestrator: jido_agent}
        {:error, _reason} -> base_session
      end

    case SessionSupervisor.start_session(session_with_orch) do
      {:ok, pid} when is_pid(pid) ->
        %{
          session_with_orch
          | metadata: Map.put(session_with_orch.metadata, :session_pid, pid)
        }

      _ ->
        session_with_orch
    end
  end

  @doc """
  Run a turn with the given user message. Returns:
    * `{:ok, reply, updated_session}` on a clean LLM completion
    * `{:halt, %ApprovalRequest{}, updated_session}` on a confirmation halt
    * `{:error, reason, updated_session}` on a runtime error
  """
  @spec run(Session.t(), String.t(), keyword()) ::
          {:ok, term(), Session.t()}
          | {:halt, ApprovalRequest.t() | Suspension.t(), Session.t()}
          | {:error, term(), Session.t()}
  def run(session, query, opts \\ [])

  def run(%Session{jido_orchestrator: nil} = session, _query, _opts) do
    {:error, :no_orchestrator, session}
  end

  def run(%Session{} = session, query, _opts) when is_binary(query) do
    pid = session_pid(session)

    if pid && not Process.alive?(pid) do
      {:error, :session_terminated, session}
    else
      module = base_orchestrator_module(session.jido_orchestrator)

      context = %{
        ash_harness_session_pid: pid,
        ash_harness_session: session,
        request_id: session.request_id
      }

      case module.query_sync(session.jido_orchestrator, query, context) do
        {:ok, agent, result} ->
          {:ok, result, sync_session_from_agent(session, agent, bump_turn: true)}

        {:suspended, agent, %Suspension{approval_request: %ApprovalRequest{} = request} = sus} ->
          synced = sync_session_from_agent(session, agent)
          synced = put_meta(synced, :pending_suspension, sus)
          {:halt, request, synced}

        {:suspended, agent, %Suspension{} = sus} ->
          synced = sync_session_from_agent(session, agent)
          synced = put_meta(synced, :pending_suspension, sus)
          {:halt, sus, synced}

        {:suspended, agent, %{approval_request: %ApprovalRequest{} = request} = sus} ->
          synced = sync_session_from_agent(session, agent)
          synced = put_meta(synced, :pending_suspension, sus)
          {:halt, request, synced}

        {:suspended, agent, suspension} ->
          synced = sync_session_from_agent(session, agent)
          synced = put_meta(synced, :pending_suspension, suspension)
          {:halt, suspension, synced}

        {:error, reason} ->
          {:error, reason, sync_session_from_agent(session, session.jido_orchestrator)}
      end
    end
  end

  @doc """
  Resume a halted session with an `%ApprovalResponse{}`.

  Hands the response to Jido's `Composer.Resume.resume/4` at the
  pending suspension point and continues `query_sync`-style. Returns
  the same shape as `run/3`.

  Falls back to v0.1.0 host-replay behavior if no pending suspension
  is recorded.
  """
  @spec resume(Session.t(), ApprovalResponse.t()) ::
          {:ok, term(), Session.t()}
          | {:halt, ApprovalRequest.t() | Suspension.t(), Session.t()}
          | {:error, term(), Session.t()}
  def resume(%Session{} = session, %ApprovalResponse{} = response) do
    session = do_record_approval(session, response)
    session = maybe_append_rejection_entry(session, response)

    case pending_suspension(session) do
      %Suspension{id: suspension_id} ->
        do_resume(session, suspension_id, response)

      _ ->
        # Fallback: behave like v0.1.0 — host re-invokes `run/3` with
        # the recorded approval already attached.
        {:ok, :resumed, session}
    end
  end

  @doc """
  Returns the session's accumulated trajectory (most recent last).
  Reads through to the SessionAgent if alive, otherwise falls back to
  the value in the struct.
  """
  @spec trajectory(Session.t()) :: [Session.trajectory_entry()]
  def trajectory(%Session{} = session) do
    case session_pid(session) do
      pid when is_pid(pid) ->
        case SessionAgent.get_state(pid) do
          %Session{trajectory: t} -> Enum.reverse(t)
          _ -> Enum.reverse(session.trajectory)
        end

      _ ->
        Enum.reverse(session.trajectory)
    end
  end

  @doc """
  Returns the count of successful mutations in the current turn.
  Reads through to the SessionAgent if alive.
  """
  @spec mutation_count(Session.t()) :: non_neg_integer()
  def mutation_count(%Session{} = session) do
    case session_pid(session) do
      pid when is_pid(pid) ->
        case SessionAgent.get_state(pid) do
          %Session{mutation_count: c} -> c
          _ -> session.mutation_count
        end

      _ ->
        session.mutation_count
    end
  end

  @doc """
  Explicitly tear down the SessionAgent backing this session.
  Idempotent.
  """
  @spec terminate(Session.t()) :: :ok
  def terminate(%Session{} = session) do
    case session_pid(session) do
      pid when is_pid(pid) -> SessionAgent.terminate(pid)
      _ -> :ok
    end
  end

  # ----------------------------------------------------------------
  # Internal helpers
  # ----------------------------------------------------------------

  @doc false
  @spec dispatch(module(), module(), atom(), map(), map()) ::
          {:ok, map()} | {:error, String.t()}
  def dispatch(agent_module, resource, action_name, params, ctx) do
    AshHarness.Harness.GeneratedAction.dispatch(
      agent_module,
      resource,
      action_name,
      params,
      ctx
    )
  end

  defp base_orchestrator_module(%Jido.Agent{agent_module: module})
       when is_atom(module) and not is_nil(module),
       do: module

  defp base_orchestrator_module(_), do: Jido.Composer.Skill.BaseOrchestrator

  defp session_pid(%Session{metadata: %{session_pid: pid}}) when is_pid(pid), do: pid
  defp session_pid(_), do: nil

  defp sync_session_from_agent(%Session{} = session, jido_agent, opts \\ []) do
    bump_turn? = Keyword.get(opts, :bump_turn, false)
    session = %{session | jido_orchestrator: jido_agent}

    case session_pid(session) do
      pid when is_pid(pid) ->
        case SessionAgent.get_state(pid) do
          %Session{} = held ->
            new_turn = if bump_turn?, do: held.turn_number + 1, else: held.turn_number

            updated = %{
              held
              | jido_orchestrator: jido_agent,
                turn_number: new_turn,
                metadata: Map.put(held.metadata, :session_pid, pid)
            }

            :ok = SessionAgent.update_session(pid, updated)
            updated

          _ ->
            session
        end

      _ ->
        if bump_turn?, do: %{session | turn_number: session.turn_number + 1}, else: session
    end
  end

  defp pending_suspension(%Session{metadata: %{pending_suspension: %Suspension{} = s}}), do: s
  defp pending_suspension(_), do: nil

  defp put_meta(%Session{metadata: meta} = session, key, value) do
    new_meta = Map.put(meta, key, value)
    new_session = %{session | metadata: new_meta}

    case session_pid(new_session) do
      pid when is_pid(pid) ->
        :ok = SessionAgent.update_session(pid, new_session)
        new_session

      _ ->
        new_session
    end
  end

  defp maybe_append_rejection_entry(
         %Session{} = session,
         %ApprovalResponse{decision: :rejected} = response
       ) do
    data = response.data || %{}
    resource = Map.get(data, :resource)
    action = Map.get(data, :action)

    intent = %Intent{
      resource: resource,
      action: action,
      input: %{},
      request_id: response.request_id
    }

    entry = %TrajectoryEntry{
      timestamp: DateTime.utc_now(),
      turn_number: session.turn_number,
      intent: intent,
      result_status: :confirmation_rejected,
      duration_ms: 0,
      metadata: %{request_id: response.request_id}
    }

    case session_pid(session) do
      pid when is_pid(pid) ->
        :ok = SessionAgent.append_trajectory(pid, entry)
        session

      _ ->
        %{session | trajectory: [entry | session.trajectory]}
    end
  end

  defp maybe_append_rejection_entry(session, _response), do: session

  defp do_record_approval(%Session{} = session, %ApprovalResponse{} = response) do
    data = response.data || %{}

    decision_key = {
      Map.get(data, :resource),
      Map.get(data, :action)
    }

    approvals = Map.get(session.metadata, :approvals, %{})
    new_approvals = Map.put(approvals, decision_key, response.decision)
    new_session = %{session | metadata: Map.put(session.metadata, :approvals, new_approvals)}

    case session_pid(new_session) do
      pid when is_pid(pid) ->
        :ok = SessionAgent.record_approval(pid, response)
        :ok = SessionAgent.update_session(pid, new_session)
        new_session

      _ ->
        new_session
    end
  end

  defp do_resume(%Session{jido_orchestrator: jido_agent} = session, suspension_id, response) do
    module = base_orchestrator_module(jido_agent)

    # Bypass `Jido.Composer.Resume.resume/4` — its `deliver_resume/4`
    # only matches suspensions in `strat.pending_suspension`,
    # `strat.suspended_calls`, or `strat.fan_out` and therefore misses
    # approval-gate suspensions (which live in
    # `strat.approval_gate.gated_calls`). The orchestrator strategy's
    # `cmd(:suspend_resume, ...)` clause handles approval-gate resumes
    # correctly via `ApprovalGate.get/2`, so dispatch directly.
    signal_params =
      response
      |> Map.from_struct()
      |> Map.put(:suspension_id, suspension_id)
      |> Map.put(:response_data, Map.from_struct(response))

    {resumed_agent, directives} = module.cmd(jido_agent, {:suspend_resume, signal_params})

    case Jido.Composer.Orchestrator.DSL.__query_sync_loop__(module, resumed_agent, directives) do
      {:ok, agent, result} ->
        {:ok, result, sync_session_from_agent(clear_pending(session), agent, bump_turn: true)}

      {:suspended, agent, %Suspension{approval_request: %ApprovalRequest{} = request} = sus} ->
        synced = sync_session_from_agent(session, agent)
        synced = put_meta(synced, :pending_suspension, sus)
        {:halt, request, synced}

      {:suspended, agent, %Suspension{} = sus} ->
        synced = sync_session_from_agent(session, agent)
        synced = put_meta(synced, :pending_suspension, sus)
        {:halt, sus, synced}

      {:error, reason} ->
        {:error, reason, sync_session_from_agent(session, resumed_agent)}
    end
  end

  defp clear_pending(%Session{metadata: meta} = session) do
    new_meta = Map.delete(meta, :pending_suspension)
    new_session = %{session | metadata: new_meta}

    case session_pid(new_session) do
      pid when is_pid(pid) ->
        # Read-modify-write through the held state so we don't clobber
        # mutable per-turn fields (trajectory, mutation_count, approvals,
        # repair_attempts) that the SessionAgent updated during dispatch.
        case SessionAgent.get_state(pid) do
          %Session{} = held ->
            held_cleared = %{held | metadata: Map.delete(held.metadata, :pending_suspension)}
            :ok = SessionAgent.update_session(pid, held_cleared)
            held_cleared

          _ ->
            new_session
        end

      _ ->
        new_session
    end
  end

  defp resolve_actor(actor) when is_function(actor, 0), do: actor.()

  defp resolve_actor({m, f, args}) when is_atom(m) and is_atom(f) and is_list(args),
    do: apply(m, f, args)

  defp resolve_actor(actor), do: actor

  defp gen_request_id,
    do: "req_" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)
end
