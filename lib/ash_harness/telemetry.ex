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
  """

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

  @doc false
  def enabled? do
    Application.get_env(:ash_harness, :telemetry, [])
    |> Keyword.get(:enabled, true)
  end

  defp maybe_attach_otel_attrs(metadata) when is_map(metadata) do
    if Code.ensure_loaded?(:otel_tracer) and Code.ensure_loaded?(:otel_span) do
      attrs =
        for {k, v} <- metadata, into: %{}, do: {otel_key(k), otel_value(v)}

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

  defp otel_value(v) when is_atom(v), do: Atom.to_string(v)
  defp otel_value(v) when is_binary(v), do: v
  defp otel_value(v) when is_integer(v) or is_float(v) or is_boolean(v), do: v
  defp otel_value(v), do: inspect(v)
end
