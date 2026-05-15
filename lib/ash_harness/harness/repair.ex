defmodule AshHarness.Harness.Repair do
  @moduledoc """
  Repair-loop helpers (formerly "Ralph Loop").

  Turns Ash errors into LLM-readable feedback strings, classifies
  retryability, and tracks per-action attempt counts via the
  session's `:repair_attempts` map.

  As of v0.1.2 the gates return structured `%AshHarness.Errors.*{}`
  errors; this module pattern-matches on those structs (no atom
  fallback) for `format_feedback/2` and `retryable?/1`.
  """

  alias AshHarness.Errors.{
    DelegationDepthExceeded,
    DelegationNotPermitted,
    MutationLimitExceeded,
    PolicyDenied,
    ReasoningRequired,
    ScopeViolation,
    ValidationFailed
  }

  alias AshHarness.Harness.Intent

  @doc """
  Format an Ash error (or any other) as a human-readable feedback
  string the LLM should consume. Sanitizes stack traces, module names,
  and internal class names.
  """
  @spec format_feedback(term(), Intent.t() | nil) :: String.t()
  def format_feedback(error, intent \\ nil)

  def format_feedback(%ValidationFailed{ash_error: %Ash.Error.Invalid{} = err}, intent) do
    format_validation(err, intent)
  end

  def format_feedback(%PolicyDenied{ash_error: %Ash.Error.Forbidden{} = err}, intent) do
    format_forbidden(err, intent)
  end

  def format_feedback(%PolicyDenied{}, intent) do
    format_forbidden(%Ash.Error.Forbidden{}, intent)
  end

  def format_feedback(%ScopeViolation{}, _intent) do
    "That action is not in scope. Choose a different tool."
  end

  def format_feedback(%ReasoningRequired{}, _intent) do
    "This action requires you to provide a `reasoning` argument before " <>
      "invoking. Include reasoning that explains the intent."
  end

  def format_feedback(%MutationLimitExceeded{}, _intent) do
    "Per-turn mutation budget exhausted. Continue with read-only work or " <>
      "ask the user for the next turn."
  end

  def format_feedback(%DelegationNotPermitted{from: from, to: to}, _intent) do
    "Delegation not permitted: #{inspect(from)} cannot delegate to " <>
      "#{inspect(to)}. Choose a different target or handle this " <>
      "yourself."
  end

  def format_feedback(%DelegationDepthExceeded{max_depth: max}, _intent) do
    "Delegation depth limit (#{inspect(max)}) reached. Handle this " <>
      "directly instead of delegating further."
  end

  def format_feedback(%Ash.Error.Invalid{} = err, intent) do
    format_validation(err, intent)
  end

  def format_feedback(%Ash.Error.Forbidden{} = err, intent) do
    format_forbidden(err, intent)
  end

  def format_feedback(:repair_exhausted, %Intent{resource: resource, action: action}) do
    "Retry limit reached for #{label_resource(resource)}.#{action}; try a " <>
      "different approach (different tool, different arguments, or ask the " <>
      "user for guidance)."
  end

  def format_feedback(:repair_exhausted, _intent) do
    "Retry limit reached; try a different approach."
  end

  def format_feedback(:confirmation_rejected, %Intent{resource: resource, action: action})
      when not is_nil(resource) and not is_nil(action) do
    "Human rejected the requested #{label_resource(resource)}.#{action}. " <>
      "Try a different approach or ask the user for guidance."
  end

  def format_feedback(:confirmation_rejected, _intent) do
    "Human rejected the requested action. " <>
      "Try a different approach or ask the user for guidance."
  end

  def format_feedback(reason, _intent) when is_atom(reason) do
    "Action failed: #{Atom.to_string(reason)}."
  end

  def format_feedback(other, _intent), do: "Action failed: #{inspect(other)}"

  defp format_validation(%Ash.Error.Invalid{errors: errors}, intent) do
    bullets =
      errors
      |> List.wrap()
      |> Enum.map_join("\n", &format_field_error/1)

    base = "Validation failed:\n" <> bullets

    case intent && accepted_parameters_hint(intent) do
      nil -> base
      hint -> base <> "\n\n" <> hint
    end
  end

  defp format_field_error(%{field: field, message: message}) when not is_nil(field),
    do: "- #{field}: #{message}"

  defp format_field_error(%{message: message}) when is_binary(message),
    do: "- general: #{message}"

  defp format_field_error(other) when is_binary(other), do: "- general: #{other}"
  defp format_field_error(other), do: "- general: #{inspect(other)}"

  defp accepted_parameters_hint(%Intent{resource: resource, action: action_name}) do
    case Ash.Resource.Info.action(resource, action_name) do
      nil ->
        nil

      %{accept: accept, arguments: args} ->
        accept_str = Enum.map_join(accept, ", ", &Atom.to_string/1)

        arg_str =
          Enum.map_join(args, ", ", fn a ->
            "#{a.name} (#{type_label(a.type)})" <>
              if(a.allow_nil?, do: "", else: " [required]")
          end)

        "Accepted parameters: #{accept_str}#{if arg_str == "", do: "", else: "; arguments: " <> arg_str}"
    end
  end

  defp label_resource(mod) when is_atom(mod) do
    mod |> Atom.to_string() |> String.replace_prefix("Elixir.", "")
  end

  defp label_resource(other), do: inspect(other)

  defp type_label(t) when is_atom(t),
    do: Atom.to_string(t) |> String.replace_prefix("Elixir.", "")

  defp type_label({:array, inner}), do: "array of #{type_label(inner)}"
  defp type_label(other), do: inspect(other)

  defp format_forbidden(%Ash.Error.Forbidden{}, intent) do
    base =
      "Authorization denied. Retrying with the same actor will not " <>
        "succeed."

    if intent_has_delegate_option?(intent),
      do: base <> " Consider delegating to another agent for this question.",
      else: base
  end

  defp intent_has_delegate_option?(%Intent{metadata: %{agent: agent}})
       when is_atom(agent) and not is_nil(agent) do
    case AshHarness.Agent.Info.delegates(agent) do
      [] -> false
      _ -> true
    end
  end

  defp intent_has_delegate_option?(_), do: false

  @doc """
  Returns `true` for retryable errors (validation, missing reasoning),
  `false` for terminal ones (policy, scope, budget, delegation,
  configuration, unexpected).

  Pattern-matches on `%AshHarness.Errors.*{}` structs only; legacy
  atom forms are no longer recognized.
  """
  @spec retryable?(term()) :: boolean()
  def retryable?(%ValidationFailed{}), do: true
  def retryable?(%ReasoningRequired{}), do: true
  def retryable?(%PolicyDenied{}), do: false
  def retryable?(%ScopeViolation{}), do: false
  def retryable?(%MutationLimitExceeded{}), do: false
  def retryable?(%DelegationNotPermitted{}), do: false
  def retryable?(%DelegationDepthExceeded{}), do: false
  def retryable?(%Ash.Error.Invalid{}), do: true
  def retryable?(%Ash.Error.Forbidden{}), do: false
  def retryable?(_), do: false
end
