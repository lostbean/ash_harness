defmodule AshHarness.Delegation.Initiate do
  @moduledoc """
  Implementation of `AshHarness.Delegation.initiate/4`.

  Holds the body of the function moved out of the historical
  monolithic `lib/ash_harness/delegation.ex`. The public module
  `AshHarness.Delegation` re-exports `initiate/4`, so callers don't see
  the relocation.

  See `design/layers/09-delegation.md` and ADR 0004 for the rationale
  behind the text-only return shape.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Delegation.Result
  alias AshHarness.Errors.DelegationDepthExceeded
  alias AshHarness.Errors.DelegationNotPermitted
  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.TrajectoryEntry
  alias AshHarness.Telemetry

  @default_max_depth 3

  @doc """
  Initiate a delegation. See `AshHarness.Delegation.initiate/4` for the
  public contract.
  """
  @spec run(Session.t(), module(), String.t(), keyword()) ::
          {:ok, String.t(), Session.t(), [TrajectoryEntry.t()]}
          | {:error, :delegate_halted}
          | {:error, DelegationNotPermitted.t()}
          | {:error, DelegationDepthExceeded.t()}
          | {:error, term()}
  def run(%Session{} = caller, target, question, opts \\ [])
      when is_atom(target) and is_binary(question) do
    max = max_depth(opts)
    depth = current_depth(caller)

    # v0.1.2 telemetry contract: each delegation carries a fresh
    # `target_trajectory_id` so observability tools can fetch the
    # delegate's full trace. Generated here at the entry point and
    # threaded into :started/:ended/:denied events plus the caller's
    # trajectory entry.
    target_trajectory_id = Uniq.UUID.uuid4()

    # `request_id` should match the parent dispatch's id when delegation
    # is invoked from a generated tool. Callers (including the
    # `Delegation.Skill`) may supply `:request_id`; we fall back to a
    # fresh UUID so the field is never nil.
    request_id = Keyword.get(opts, :request_id) || Uniq.UUID.uuid4()

    cond do
      not AgentInfo.delegate_for?(caller.agent, target) ->
        emit_denied(caller, target, :not_permitted, target_trajectory_id, request_id)
        {:error, %DelegationNotPermitted{from: caller.agent, to: target, reason: :not_permitted}}

      depth >= max ->
        emit_denied(caller, target, :depth_exceeded, target_trajectory_id, request_id)

        {:error,
         %DelegationDepthExceeded{
           from: caller.agent,
           to: target,
           depth: depth,
           max_depth: max
         }}

      true ->
        do_initiate(caller, target, question, opts, target_trajectory_id, request_id)
    end
  end

  defp do_initiate(caller, target, question, opts, target_trajectory_id, request_id) do
    depth = current_depth(caller) + 1
    started_at = System.monotonic_time(:millisecond)

    Telemetry.emit(
      [:ash_harness, :delegation, :started],
      %{depth: depth},
      %{
        from_agent: caller.agent,
        to_agent: target,
        depth: depth,
        target_trajectory_id: target_trajectory_id,
        request_id: request_id
      }
    )

    target_opts =
      opts
      |> Keyword.drop([:request_id, :max_depth])
      |> Keyword.put(:metadata, %{_delegation_depth: depth})

    delegate_session = Harness.new_session(target, target_opts)

    case Harness.run(delegate_session, question) do
      {:ok, reply, final_delegate_session} ->
        reply_text = stringify(reply)
        duration = System.monotonic_time(:millisecond) - started_at

        entry = %TrajectoryEntry{
          timestamp: DateTime.utc_now(),
          turn_number: caller.turn_number,
          intent: %{type: :delegation, target: target, question: question},
          result_status: :ok,
          duration_ms: duration,
          data: %{
            reply_text: reply_text,
            target_trajectory_id: target_trajectory_id
          }
        }

        updated_caller = append_trajectory(caller, entry)

        Telemetry.emit(
          [:ash_harness, :delegation, :ended],
          %{duration_ms: duration},
          %{
            from_agent: caller.agent,
            to_agent: target,
            status: :ok,
            depth: depth,
            target_trajectory_id: target_trajectory_id,
            request_id: request_id
          }
        )

        result = %Result{
          reply_text: reply_text,
          target_trajectory_id: target_trajectory_id,
          target_trajectory: Harness.trajectory(final_delegate_session),
          status: :ok
        }

        {:ok, result.reply_text, updated_caller, result.target_trajectory}

      {:halt, _halt_payload, _session} ->
        Telemetry.emit(
          [:ash_harness, :delegation, :ended],
          %{duration_ms: System.monotonic_time(:millisecond) - started_at},
          %{
            from_agent: caller.agent,
            to_agent: target,
            status: :halt,
            depth: depth,
            target_trajectory_id: target_trajectory_id,
            request_id: request_id
          }
        )

        {:error, :delegate_halted}

      {:error, reason, _session} ->
        Telemetry.emit(
          [:ash_harness, :delegation, :ended],
          %{duration_ms: System.monotonic_time(:millisecond) - started_at},
          %{
            from_agent: caller.agent,
            to_agent: target,
            status: :error,
            depth: depth,
            target_trajectory_id: target_trajectory_id,
            request_id: request_id
          }
        )

        {:error, reason}
    end
  end

  defp emit_denied(caller, target, reason, target_trajectory_id, request_id) do
    Telemetry.emit(
      [:ash_harness, :delegation, :denied],
      %{},
      %{
        from_agent: caller.agent,
        to_agent: target,
        reason: reason,
        target_trajectory_id: target_trajectory_id,
        request_id: request_id
      }
    )
  end

  defp current_depth(%Session{metadata: meta}) do
    Map.get(meta || %{}, :_delegation_depth, 0)
  end

  defp max_depth(opts) do
    case Keyword.fetch(opts, :max_depth) do
      {:ok, n} when is_integer(n) and n > 0 ->
        n

      _ ->
        Application.get_env(:ash_harness, :delegation_max_depth, @default_max_depth)
    end
  end

  defp stringify(s) when is_binary(s), do: s
  defp stringify(:resumed), do: ""
  defp stringify(nil), do: ""
  defp stringify(v), do: inspect(v)

  defp append_trajectory(%Session{trajectory: trajectory} = session, entry) do
    case session.metadata[:session_pid] do
      pid when is_pid(pid) ->
        :ok = AshHarness.Harness.SessionAgent.append_trajectory(pid, entry)
        %{session | trajectory: [entry | trajectory]}

      _ ->
        %{session | trajectory: [entry | trajectory]}
    end
  end
end
