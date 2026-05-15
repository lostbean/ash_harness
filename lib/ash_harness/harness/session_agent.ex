defmodule AshHarness.Harness.SessionAgent do
  @moduledoc """
  GenServer that holds the mutable parts of a session for the duration
  of a turn: mutation_count, trajectory, repair_attempts, and recorded
  approvals.

  `AshHarness.Harness.new_session/2` starts one under
  `AshHarness.Harness.SessionSupervisor`. The pid lands in
  `session.metadata.session_pid` and travels with the orchestrator's
  context as `ctx[:ash_harness_session_pid]` so
  `GeneratedAction.dispatch/5` can mutate during a turn.
  """

  use GenServer

  alias AshHarness.Harness.Session
  alias AshHarness.Harness.TrajectoryEntry
  alias Jido.Composer.HITL.ApprovalResponse

  # ----------------------------------------------------------------
  # Public API
  # ----------------------------------------------------------------

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    session = Keyword.fetch!(opts, :session)
    GenServer.start_link(__MODULE__, session)
  end

  @doc """
  Fetch the current `%Session{}` snapshot held by this agent.
  Returns `{:error, :session_terminated}` if the process is down.
  """
  @spec get_state(pid()) :: Session.t() | {:error, :session_terminated}
  def get_state(pid) do
    if Process.alive?(pid) do
      GenServer.call(pid, :get_state)
    else
      {:error, :session_terminated}
    end
  catch
    :exit, _ -> {:error, :session_terminated}
  end

  @doc """
  Replace the session held by the agent. Useful for re-syncing after
  the host updated a value-typed field like `:jido_orchestrator`.
  """
  @spec update_session(pid(), Session.t()) :: :ok
  def update_session(pid, %Session{} = session) do
    GenServer.call(pid, {:update_session, session})
  end

  @doc """
  Apply an arbitrary update function to the held session. The function
  receives the current `%Session{}` and must return a new one.
  """
  @spec update_session(pid(), (Session.t() -> Session.t())) :: :ok
  def update_session_with(pid, fun) when is_function(fun, 1) do
    GenServer.call(pid, {:update_session_with, fun})
  end

  @doc """
  Increment the session's mutation counter. Returns the new count.
  """
  @spec bump_mutation(pid()) :: non_neg_integer()
  def bump_mutation(pid) do
    GenServer.call(pid, :bump_mutation)
  end

  @doc """
  Append a `%TrajectoryEntry{}` to the session trajectory. Most recent
  entries are stored at the head; `Harness.trajectory/1` reverses.
  """
  @spec append_trajectory(pid(), TrajectoryEntry.t()) :: :ok
  def append_trajectory(pid, %TrajectoryEntry{} = entry) do
    GenServer.call(pid, {:append_trajectory, entry})
  end

  @doc """
  Bump the repair-attempt counter for a given `{resource, action}`.
  Returns the new attempt count.
  """
  @spec bump_repair_attempt(pid(), {module(), atom()}) :: non_neg_integer()
  def bump_repair_attempt(pid, {_resource, _action} = key) do
    GenServer.call(pid, {:bump_repair_attempt, key})
  end

  @doc """
  Read the current repair-attempt count for a `{resource, action}`.
  """
  @spec repair_attempts(pid(), {module(), atom()}) :: non_neg_integer()
  def repair_attempts(pid, {_resource, _action} = key) do
    GenServer.call(pid, {:repair_attempts, key})
  end

  @doc """
  Record an `%ApprovalResponse{}` against its `{resource, action}`
  key, so the ConfirmationGate sees it on the next pass. Once an
  action is approved in a session, it remains approved until the
  approval is cleared or the session ends.
  """
  @spec record_approval(pid(), ApprovalResponse.t()) :: :ok
  def record_approval(pid, %ApprovalResponse{} = response) do
    GenServer.call(pid, {:record_approval, response})
  end

  @doc """
  Increment the session's turn_number. Returns the new turn number.
  """
  @spec bump_turn(pid()) :: non_neg_integer()
  def bump_turn(pid) do
    GenServer.call(pid, :bump_turn)
  end

  @doc """
  Stop the SessionAgent. Idempotent — already-dead pids return `:ok`.
  """
  @spec terminate(pid()) :: :ok
  def terminate(pid) do
    if Process.alive?(pid) do
      _ = GenServer.stop(pid, :normal, :infinity)
      :ok
    else
      :ok
    end
  catch
    :exit, _ -> :ok
  end

  # ----------------------------------------------------------------
  # GenServer callbacks
  # ----------------------------------------------------------------

  @impl true
  def init(%Session{} = session) do
    # Record the SessionAgent's pid on the held state so code that
    # only has the `%Session{}` (e.g. `Delegation.Initiate.run/4`,
    # invoked from `Delegation.Skill` after a `get_state` lookup) can
    # reach the SessionAgent without an out-of-band pid handle.
    session = %{session | metadata: Map.put(session.metadata, :session_pid, self())}
    {:ok, session}
  end

  @impl true
  def handle_call(:get_state, _from, %Session{} = state) do
    {:reply, state, state}
  end

  def handle_call({:update_session, %Session{} = session}, _from, _state) do
    {:reply, :ok, session}
  end

  def handle_call({:update_session_with, fun}, _from, state) do
    new_state = fun.(state)
    {:reply, :ok, new_state}
  end

  def handle_call(:bump_mutation, _from, %Session{mutation_count: c} = state) do
    new_count = c + 1
    {:reply, new_count, %{state | mutation_count: new_count}}
  end

  def handle_call({:append_trajectory, entry}, _from, %Session{trajectory: t} = state) do
    {:reply, :ok, %{state | trajectory: [entry | t]}}
  end

  def handle_call({:bump_repair_attempt, key}, _from, %Session{repair_attempts: ra} = state) do
    new_count = Map.get(ra, key, 0) + 1
    new_ra = Map.put(ra, key, new_count)
    {:reply, new_count, %{state | repair_attempts: new_ra}}
  end

  def handle_call({:repair_attempts, key}, _from, %Session{repair_attempts: ra} = state) do
    {:reply, Map.get(ra, key, 0), state}
  end

  def handle_call({:record_approval, %ApprovalResponse{} = response}, _from, state) do
    data = response.data || %{}

    decision_key = {
      Map.get(data, :resource),
      Map.get(data, :action)
    }

    # v0.1.2: store the full approval record so the ConfirmationGate's
    # `:approved` event can include `respondent` + `duration_ms` without
    # re-plumbing the response through every dispatch.
    entry = %{
      decision: response.decision,
      respondent: response.respondent || :unspecified,
      duration_ms: Map.get(data, :duration_ms),
      responded_at: response.responded_at
    }

    new_meta =
      Map.update(state.metadata, :approvals, %{decision_key => entry}, fn approvals ->
        Map.put(approvals, decision_key, entry)
      end)

    {:reply, :ok, %{state | metadata: new_meta}}
  end

  def handle_call(:bump_turn, _from, %Session{turn_number: t} = state) do
    new_turn = t + 1
    {:reply, new_turn, %{state | turn_number: new_turn}}
  end
end
