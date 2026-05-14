defmodule AshHarness.Telemetry do
  @moduledoc """
  AshHarness telemetry events under the `[:ash_harness, …]` namespace.

  ## Events

  Gate pipeline:
    * `[:ash_harness, :scope, :violation]`
    * `[:ash_harness, :reasoning, :missing]`
    * `[:ash_harness, :confirmation, :requested | :approved | :rejected]`
    * `[:ash_harness, :budget, :exceeded]`
    * `[:ash_harness, :policy, :denied]`

  Action execution:
    * `[:ash_harness, :action, :executed]` — with `:duration_ms` measurement and
      `:agent`, `:resource`, `:action`, `:status` metadata.

  Repair loop:
    * `[:ash_harness, :repair, :feedback]`
    * `[:ash_harness, :repair, :exhausted]`

  Delegation:
    * `[:ash_harness, :delegation, :started | :ended | :denied]`

  Context renderer:
    * `[:ash_harness, :context, :rendered]`

  Eval:
    * `[:ash_harness, :eval, :scenario, :start | :stop]`
    * `[:ash_harness, :eval, :gate, :checked]`
    * `[:ash_harness, :eval, :report, :computed]`

  ## Disabling

  Set `config :ash_harness, :telemetry, enabled: false` to suppress all
  event emissions.

  ## OpenTelemetry attributes

  When an event fires inside an active OTel span, the emitter also calls
  `OpenTelemetry.Tracer.set_attributes/1` with `ash_harness.*` keys.

  In addition to the auto-mirrored event metadata, the harness sets the
  following spec-required attributes on the active span at well-defined
  points in the dispatch lifecycle via `set_otel_attribute/2`:

    * `ash_harness.scope.passed` (boolean)
    * `ash_harness.policy.passed` (boolean)
    * `ash_harness.budget.count` (integer)
    * `ash_harness.budget.max` (integer)
    * `ash_harness.repair.attempt` (integer)
    * `ash_harness.session.id` (string)
    * `ash_harness.request.id` (string)
  """

  @otel_capture_key :ash_harness_test_otel_capture

  @doc """
  Emit a telemetry event. Respects `config :ash_harness, :telemetry,
  enabled: bool` (default true).

  Also attaches `ash_harness.*` attributes to the active OpenTelemetry
  span when one is set.
  """
  @spec emit([atom()], map(), map()) :: :ok
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    if enabled?() do
      :telemetry.execute(event, measurements, metadata)
      maybe_attach_otel_attrs(metadata)
    end

    :ok
  end

  @doc """
  Set a single `ash_harness.<key>` attribute on the active OpenTelemetry
  span. The argument `key` is the suffix after the `ash_harness.`
  namespace (e.g. `"scope.passed"` produces `ash_harness.scope.passed`).

  No-op when the OTel SDK isn't loaded and no test capture is active.
  Used by the dispatch pipeline to record spec-required attributes that
  aren't otherwise carried in event metadata (e.g. gate-pass booleans,
  budget counters, repair attempts, session/request ids).
  """
  @spec set_otel_attribute(String.t() | atom(), term()) :: :ok
  def set_otel_attribute(key, value) do
    capture_or_call_otel(%{otel_key(key) => otel_value(value)})
    :ok
  end

  @doc """
  Bulk variant of `set_otel_attribute/2` — accepts a map of `key =>
  value` entries (keys are suffixes after `ash_harness.`).
  """
  @spec set_otel_attributes(map() | keyword()) :: :ok
  def set_otel_attributes(attrs) when is_map(attrs) or is_list(attrs) do
    normalized =
      for {k, v} <- attrs, into: %{}, do: {otel_key(k), otel_value(v)}

    capture_or_call_otel(normalized)
    :ok
  end

  @doc false
  def enabled? do
    Application.get_env(:ash_harness, :telemetry, [])
    |> Keyword.get(:enabled, true)
  end

  # Test-only helper. Runs `fun` with OTel attribute writes routed into
  # a process-local capture list instead of dispatched to the real OTel
  # SDK. Returns the list of recorded attribute maps in the order they
  # were written. Intended for verifying that `set_otel_attribute/2` /
  # `set_otel_attributes/1` are called with the expected keys from
  # inside the dispatch pipeline; production code paths are unaffected
  # outside this wrapper.
  @doc false
  @spec __with_captured_otel__((-> any())) :: [map()]
  def __with_captured_otel__(fun) when is_function(fun, 0) do
    Process.put(@otel_capture_key, [])

    try do
      fun.()
      Process.get(@otel_capture_key, []) |> Enum.reverse()
    after
      Process.delete(@otel_capture_key)
    end
  end

  defp maybe_attach_otel_attrs(metadata) when is_map(metadata) do
    attrs =
      for {k, v} <- metadata, into: %{}, do: {otel_key(k), otel_value(v)}

    capture_or_call_otel(attrs)
    :ok
  end

  defp capture_or_call_otel(attrs) when is_map(attrs) do
    case Process.get(@otel_capture_key) do
      nil ->
        call_otel_sdk(attrs)

      list when is_list(list) ->
        Process.put(@otel_capture_key, [attrs | list])
        :ok
    end
  end

  defp call_otel_sdk(attrs) do
    if Code.ensure_loaded?(:otel_tracer) and Code.ensure_loaded?(:otel_span) do
      try do
        apply(:otel_span, :set_attributes, [
          apply(:otel_tracer, :current_span_ctx, []),
          attrs
        ])
      rescue
        _ -> :ok
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  defp otel_key(k) when is_atom(k), do: "ash_harness.#{Atom.to_string(k)}"
  defp otel_key(k) when is_binary(k), do: "ash_harness.#{k}"
  defp otel_key(k), do: "ash_harness.#{inspect(k)}"

  defp otel_value(v) when is_atom(v) and not is_boolean(v) and not is_nil(v),
    do: Atom.to_string(v)

  defp otel_value(v) when is_binary(v), do: v
  defp otel_value(v) when is_integer(v) or is_float(v) or is_boolean(v), do: v
  defp otel_value(nil), do: nil
  defp otel_value(v), do: inspect(v)
end
