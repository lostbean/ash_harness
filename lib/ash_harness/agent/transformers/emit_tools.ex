defmodule AshHarness.Agent.Transformers.EmitTools do
  @moduledoc """
  Emits the per-action `Jido.Action` modules and per-resource Skill
  helpers for the agent. Uses `Spark.Dsl.Transformer.eval/3` to inject
  the AST into the agent module's compile.

  Runs after `ComputeToolSet` (which populates the canonical tool
  list).
  """

  use Spark.Dsl.Transformer

  alias AshHarness.Agent.Delegation.DelegateEntry
  alias AshHarness.Agent.Scope.ResourceEntry
  alias AshHarness.Schema.Canonical
  alias AshHarness.ToolGen
  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshHarness.Agent.Transformers.ComputeToolSet), do: true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    agent_module = Transformer.get_persisted(dsl_state, :module)
    tools = Transformer.get_persisted(dsl_state, :tool_list, [])

    action_blocks =
      Enum.map(tools, fn %Canonical{} = canonical ->
        ToolGen.ActionModule.quoted(agent_module, canonical)
      end)

    scope_entries =
      dsl_state
      |> Transformer.get_entities([:scope])
      |> Enum.filter(&match?(%ResourceEntry{}, &1))

    skill_blocks =
      Enum.map(scope_entries, fn %ResourceEntry{module: resource, actions: actions} ->
        action_modules =
          for action_name <- actions do
            canonical =
              Enum.find(tools, fn c -> c.resource == resource and c.action_name == action_name end)

            if canonical, do: ToolGen.action_module(agent_module, canonical)
          end
          |> Enum.reject(&is_nil/1)

        ToolGen.SkillModule.quoted(agent_module, resource, action_modules)
      end)

    confirm_before =
      dsl_state
      |> Transformer.get_option([:behavior], :confirm_before, [])
      |> List.wrap()

    identity_name = Transformer.get_option(dsl_state, [:identity], :name)
    model = Transformer.get_option(dsl_state, [:identity], :model)

    has_delegates? =
      dsl_state
      |> Transformer.get_entities([:delegates_to])
      |> Enum.any?(&match?(%DelegateEntry{}, &1))

    orchestrator_block =
      ToolGen.OrchestratorModule.quoted(
        agent_module,
        tools,
        confirm_before,
        identity_name,
        model,
        has_delegates?
      )

    block = {:__block__, [], action_blocks ++ skill_blocks ++ [orchestrator_block]}

    {:ok, Transformer.eval(dsl_state, [], block)}
  end
end
