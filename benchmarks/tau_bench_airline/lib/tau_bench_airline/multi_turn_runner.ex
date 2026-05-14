defmodule TauBenchAirline.MultiTurnRunner do
  @moduledoc """
  Multi-turn loop between the airline agent and a user-simulator
  agent. Stops when the simulator declares its goal met (via a
  structured `:done` signal in its reply) or when `max_turns`
  (default 12) is reached.
  """

  @default_max_turns 12

  @doc """
  Run a single conversation between `agent_session` and
  `simulator_session`, returning a tuple
  `{:ok, transcript, terminated_reason}`.

  `terminated_reason` is `:goal_met` or `:max_turns`.
  """
  @spec run(map(), map(), keyword()) :: {:ok, [String.t()], atom()}
  def run(agent_session, simulator_session, opts \\ []) do
    max_turns = Keyword.get(opts, :max_turns, @default_max_turns)
    seed_question = Keyword.get(opts, :seed_question, "Hello, how can I help?")

    loop(agent_session, simulator_session, seed_question, [], 0, max_turns)
  end

  defp loop(_agent, _sim, _msg, transcript, turn, max) when turn >= max do
    {:ok, Enum.reverse(transcript), :max_turns}
  end

  defp loop(agent_session, simulator_session, message, transcript, turn, max) do
    case AshHarness.Harness.run(simulator_session, message) do
      {:ok, sim_reply, _new_sim} ->
        sim_text = stringify(sim_reply)
        transcript = ["customer: " <> sim_text | transcript]

        if goal_met?(sim_text) do
          {:ok, Enum.reverse(transcript), :goal_met}
        else
          case AshHarness.Harness.run(agent_session, sim_text) do
            {:ok, agent_reply, _new_agent} ->
              agent_text = stringify(agent_reply)
              transcript = ["agent: " <> agent_text | transcript]

              loop(agent_session, simulator_session, agent_text, transcript, turn + 1, max)

            {:halt, _request, _agent} ->
              # In eval mode we auto-approve; if the host doesn't, halt
              # is terminal.
              {:ok, Enum.reverse(transcript), :halted}

            {:error, _reason, _agent} ->
              {:ok, Enum.reverse(transcript), :error}
          end
        end

      _ ->
        {:ok, Enum.reverse(transcript), :error}
    end
  end

  defp stringify(s) when is_binary(s), do: s
  defp stringify(other), do: inspect(other)

  defp goal_met?(text) when is_binary(text) do
    Regex.match?(~r/\b(goal[- ]?met|done|all set)\b/i, text)
  end

  defp goal_met?(_), do: false
end
