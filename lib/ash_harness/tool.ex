defmodule AshHarness.Tool do
  @moduledoc """
  Public surface for building tools that aren't covered by the
  compile-time `Jido.Action` modules — e.g., session-scoped helpers,
  conditional tools, or host-app injections.

  Use `AshHarness.Tool.dynamic/2` to create a runtime tool that flows
  through the same scope/reasoning/budget/policy gate pipeline as
  compile-time tools.
  """

  alias AshHarness.Schema.Canonical

  defstruct [
    :name,
    :description,
    :schema,
    :input_builder,
    :resource,
    :action,
    :canonical
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t(),
          schema: keyword(),
          input_builder: (map() -> map()) | nil,
          resource: module() | nil,
          action: atom() | nil,
          canonical: Canonical.t() | nil
        }

  @doc """
  Builds a dynamic tool value at session-start time.

  ## Options

    * `:name` — required string.
    * `:description` — required string.
    * `:resource` — Ash resource module (required when wrapping an Ash action).
    * `:action` — atom action name.
    * `:input_builder` — `(map() -> map())` to massage input before dispatch.
    * `:schema` — optional NimbleOptions schema (auto-derived when
      `:resource` and `:action` are given).
  """
  @spec dynamic(keyword(), keyword()) :: t()
  def dynamic(opts, _extra \\ []) when is_list(opts) do
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    resource = Keyword.get(opts, :resource)
    action = Keyword.get(opts, :action)
    input_builder = Keyword.get(opts, :input_builder)

    canonical =
      if resource && action do
        AshHarness.Schema.canonical_for(resource, action)
      end

    schema =
      Keyword.get_lazy(opts, :schema, fn ->
        if canonical, do: AshHarness.ToolGen.nimble_schema(canonical), else: []
      end)

    %__MODULE__{
      name: name,
      description: description,
      schema: schema,
      input_builder: input_builder,
      resource: resource,
      action: action,
      canonical: canonical
    }
  end

  @doc """
  Dispatch a dynamic tool through the harness gate pipeline. Returns the
  same shape as `Jido.Action.run/2`: `{:ok, result_map}` or
  `{:error, feedback_string}`.

  `ctx` must carry `:ash_harness_session_pid` (and optionally
  `:ash_harness_session`, `:request_id`), as the compile-time tools do.

  `AshHarness.Harness.GeneratedAction.dispatch/5` is the shared dispatch
  entry point — both compile-time and dynamic tools route through it,
  giving identical gate semantics.
  """
  @spec run(t(), map(), map()) :: {:ok, map()} | {:error, String.t()}
  def run(%__MODULE__{resource: nil}, _params, _ctx) do
    {:error, "Dynamic tool has no :resource configured"}
  end

  def run(%__MODULE__{action: nil}, _params, _ctx) do
    {:error, "Dynamic tool has no :action configured"}
  end

  def run(%__MODULE__{resource: resource, action: action, input_builder: builder}, params, ctx)
      when is_atom(resource) and is_atom(action) do
    agent_module =
      Map.get(ctx, :ash_harness_session, %{}) |> Map.get(:agent) ||
        Map.get(ctx, :agent)

    if is_nil(agent_module) do
      {:error, "Dynamic tool dispatch requires :ash_harness_session in ctx with an :agent"}
    else
      final_params = if builder, do: builder.(params), else: params

      AshHarness.Harness.GeneratedAction.dispatch(
        agent_module,
        resource,
        action,
        final_params,
        ctx
      )
    end
  end
end
