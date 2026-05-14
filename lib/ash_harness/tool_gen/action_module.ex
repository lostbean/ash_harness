defmodule AshHarness.ToolGen.ActionModule do
  @moduledoc """
  Compile-time emitter for a `Jido.Action` module per scoped
  (resource, action) pair. The emitted module's `run/2` delegates to
  `AshHarness.Harness.GeneratedAction.dispatch/5`.

  The emitter is invoked from
  `AshHarness.Agent.Transformers.EmitTools` via
  `Spark.Dsl.Transformer.eval/3`.
  """

  alias AshHarness.Schema.Canonical
  alias AshHarness.ToolGen

  @doc """
  Returns the AST that defines the action module. Embedded in the
  agent's DSL state via `Transformer.eval/3`.
  """
  @spec quoted(module(), Canonical.t()) :: Macro.t()
  def quoted(agent_module, %Canonical{} = canonical) do
    module_name = ToolGen.action_module(agent_module, canonical)
    schema = ToolGen.nimble_schema(canonical)

    quote do
      defmodule unquote(module_name) do
        @moduledoc false
        use Jido.Action,
          name: unquote(canonical.tool_name),
          description: unquote(canonical.description),
          schema: unquote(Macro.escape(schema))

        @agent unquote(agent_module)
        @resource unquote(canonical.resource)
        @action_name unquote(canonical.action_name)
        @canonical unquote(Macro.escape(canonical))

        @doc false
        def __agent__, do: @agent
        @doc false
        def __resource__, do: @resource
        @doc false
        def __action_name__, do: @action_name
        @doc false
        def __canonical__, do: @canonical

        @impl true
        def run(params, ctx) do
          ambient_key = Jido.Composer.Context.ambient_key()
          {ambient, params} = Map.pop(params, ambient_key, %{})

          ctx =
            ctx
            |> Map.put_new(:ash_harness_session_pid, ambient[:ash_harness_session_pid])
            |> Map.put_new(:ash_harness_session, ambient[:ash_harness_session])
            |> Map.put_new(:request_id, ambient[:request_id])

          AshHarness.Harness.GeneratedAction.dispatch(
            @agent,
            @resource,
            @action_name,
            params,
            ctx
          )
        end
      end
    end
  end
end
