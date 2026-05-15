defmodule AshHarness.Delegation.Skill do
  @moduledoc """
  Meta-tool that the LLM invokes to delegate a question to another
  agent. Mirrors the `AshHarness.Harness.LoadResourceSkill` wiring:
  added to the orchestrator's `tool_nodes/0` only when the agent's
  `delegates_to` block is non-empty, and never gated by
  `requires_approval` (ADR 0004 — delegation returns text only).

  Behavior summary:

    * `target` is resolved case-insensitively against the agent's
      declared `delegate ..., as: "<alias>"` entries.
    * On match → calls `AshHarness.Delegation.initiate/4` and returns
      the delegate's reply string in `{:ok, %{reply: "..."}}`.
    * On no match → returns `{:error, "Unknown delegate target ..."}` —
      `initiate/4` is **not** called.
    * On `{:error, :delegate_halted}` (the child suspended on its own
      confirmation gate) → returns
      `{:error, "delegate halted: requires confirmation"}` per the
      v0.1.2 nested-HITL deferral (design.md open question).

  The skill threads the parent's `request_id` from ambient context (or
  generates a fresh UUID) into `initiate/4`'s `:request_id` opt so the
  delegation's `:started`/`:ended` events correlate with the parent's
  dispatch.
  """

  use Jido.Action,
    name: "delegate",
    description:
      "Delegate a question to another agent by alias. Use when the question is " <>
        "outside your scope but inside another agent's. Returns the delegate's " <>
        "text reply only.",
    schema: [
      target: [
        type: :string,
        required: true,
        doc:
          "Short alias of the delegate agent (matches the `as:` value on the " <>
            "agent's `delegate` entry, case-insensitive)."
      ],
      question: [
        type: :string,
        required: true,
        doc: "The natural-language question to ask the delegate."
      ]
    ]

  alias AshHarness.Agent.Delegation.DelegateEntry
  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.Delegation
  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent

  @impl true
  def run(params, _ctx) do
    ambient_key = Jido.Composer.Context.ambient_key()
    {ambient, params} = Map.pop(params, ambient_key, %{})

    target = string_param(params, :target)
    question = string_param(params, :question)
    pid = ambient[:ash_harness_session_pid]
    request_id = ambient[:request_id] || Uniq.UUID.uuid4()

    cond do
      target == "" ->
        {:error, "delegate requires a non-empty target alias"}

      question == "" ->
        {:error, "delegate requires a non-empty question"}

      not is_pid(pid) ->
        {:error, "delegate skill called without a session pid"}

      not Process.alive?(pid) ->
        {:error, "session has terminated"}

      true ->
        dispatch(pid, target, question, request_id)
    end
  rescue
    e -> {:error, "delegate skill error: #{Exception.message(e)}"}
  end

  defp dispatch(pid, target, question, request_id) do
    case SessionAgent.get_state(pid) do
      %Session{agent: agent_module} = caller ->
        case resolve_target(agent_module, target) do
          {:ok, %DelegateEntry{agent_module: delegate_mod}} ->
            invoke(caller, delegate_mod, question, request_id)

          :error ->
            {:error, unknown_target_message(agent_module, target)}
        end

      _ ->
        {:error, "delegate skill could not read parent session"}
    end
  end

  defp invoke(%Session{} = caller, delegate_mod, question, request_id) do
    # Forward the parent's session options (e.g. `:req_options` for the
    # LLM transport) to the child session so a host that wires an
    # LLM-stub plug for the parent gets the same stub on the child.
    opts =
      caller.options
      |> Keyword.take([:req_options, :temperature, :max_tokens, :max_iterations])
      |> Keyword.put(:request_id, request_id)

    case Delegation.initiate(caller, delegate_mod, question, opts) do
      {:ok, reply, _updated_caller, _delegate_trajectory} ->
        {:ok, %{reply: reply}}

      {:error, :delegate_halted} ->
        {:error, "delegate halted: requires confirmation"}

      {:error, %AshHarness.Errors.DelegationNotPermitted{} = err} ->
        {:error, Exception.message(err)}

      {:error, %AshHarness.Errors.DelegationDepthExceeded{} = err} ->
        {:error, Exception.message(err)}

      {:error, reason} ->
        {:error, "delegate failed: #{format_reason(reason)}"}
    end
  end

  defp resolve_target(agent_module, target) when is_binary(target) do
    needle = String.downcase(target)

    case Enum.find(AgentInfo.delegates(agent_module), fn %DelegateEntry{as: a} ->
           is_binary(a) and String.downcase(a) == needle
         end) do
      %DelegateEntry{} = entry -> {:ok, entry}
      nil -> :error
    end
  end

  defp unknown_target_message(agent_module, target) do
    aliases =
      agent_module
      |> AgentInfo.delegates()
      |> Enum.map(fn %DelegateEntry{as: a} -> a end)
      |> Enum.reject(&is_nil/1)

    formatted =
      case aliases do
        [] -> "(none declared)"
        list -> Enum.map_join(list, ", ", &inspect/1)
      end

    "Unknown delegate target #{inspect(target)}. Available aliases: #{formatted}"
  end

  defp string_param(params, key) do
    val = params[key] || params[Atom.to_string(key)]
    if is_binary(val), do: val, else: ""
  end

  defp format_reason(struct) when is_exception(struct), do: Exception.message(struct)
  defp format_reason(reason), do: inspect(reason)
end
