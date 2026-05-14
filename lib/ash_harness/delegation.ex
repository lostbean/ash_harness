defmodule AshHarness.Delegation do
  @moduledoc """
  Cross-agent delegation. The caller's `delegates_to` section lists
  allowed targets; depth is capped (default 3); the delegate runs in a
  fresh session with its own actor; the reply is a text string only.

  See `design/layers/09-delegation.md` (and ADR 0004) for the rationale
  behind the text-only return shape.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Harness
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.TrajectoryEntry
  alias AshHarness.Telemetry

  @default_max_depth 3

  @doc """
  Initiate a delegation. Returns:
    * `{:ok, reply_text, updated_caller_session, delegate_trajectory}`
    * `{:error, :delegation_not_permitted}`
    * `{:error, :delegation_depth_exceeded}`
    * `{:error, term()}`

  ## Options
    * `:max_depth` — overrides the configured cap.
  """
  @spec initiate(Session.t(), module(), String.t(), keyword()) ::
          {:ok, String.t(), Session.t(), [TrajectoryEntry.t()]}
          | {:error, :delegation_not_permitted}
          | {:error, :delegation_depth_exceeded}
          | {:error, term()}
  def initiate(%Session{} = caller, target, question, opts \\ [])
      when is_atom(target) and is_binary(question) do
    cond do
      not AgentInfo.delegate_for?(caller.agent, target) ->
        emit_denied(caller, target, :not_permitted)
        {:error, :delegation_not_permitted}

      current_depth(caller) >= max_depth(opts) ->
        emit_denied(caller, target, :depth_exceeded)
        {:error, :delegation_depth_exceeded}

      true ->
        do_initiate(caller, target, question, opts)
    end
  end

  defp do_initiate(caller, target, question, opts) do
    depth = current_depth(caller) + 1
    started_at = System.monotonic_time(:millisecond)

    Telemetry.emit(
      [:ash_harness, :delegation, :started],
      %{depth: depth},
      %{from_agent: caller.agent, to_agent: target}
    )

    target_opts = Keyword.put(opts, :metadata, %{_delegation_depth: depth})

    delegate_session = Harness.new_session(target, target_opts)

    case Harness.run(delegate_session, question) do
      {:ok, reply, final_delegate_session} ->
        reply_text = stringify(reply)

        updated_caller =
          append_trajectory(caller, %TrajectoryEntry{
            timestamp: DateTime.utc_now(),
            turn_number: caller.turn_number,
            intent: %{type: :delegation, target: target, question: question},
            result_status: :ok,
            duration_ms: System.monotonic_time(:millisecond) - started_at
          })

        Telemetry.emit(
          [:ash_harness, :delegation, :ended],
          %{duration_ms: System.monotonic_time(:millisecond) - started_at},
          %{from_agent: caller.agent, to_agent: target, status: :ok}
        )

        {:ok, reply_text, updated_caller, Harness.trajectory(final_delegate_session)}

      {:halt, _request, _session} ->
        {:error, :delegate_halted}

      {:error, reason, _session} ->
        Telemetry.emit(
          [:ash_harness, :delegation, :ended],
          %{},
          %{from_agent: caller.agent, to_agent: target, status: :error}
        )

        {:error, reason}
    end
  end

  defp emit_denied(caller, target, reason) do
    Telemetry.emit(
      [:ash_harness, :delegation, :denied],
      %{},
      %{from_agent: caller.agent, to_agent: target, reason: reason}
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
    %{session | trajectory: [entry | trajectory]}
  end
end
