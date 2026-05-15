defmodule AshHarness.ToolGen.OrchestratorModule do
  @moduledoc """
  Compile-time emitter for a per-agent `Orchestrator` module.

  The generated module `use Jido.Composer.Orchestrator` with an empty
  initial node list and is finalized at runtime — see
  `AshHarness.Harness.OrchestratorFactory.build/1`, which calls
  `MyAgent.Orchestrator.new() |> MyAgent.Orchestrator.configure(nodes:
  [...], system_prompt: ...)`. We keep nodes out of compile-time
  because Jido's orchestrator DSL `Code.ensure_loaded!`s every node
  module during macro expansion, and the action modules we want to
  list are emitted in the same compile pass and haven't loaded yet.

  The agent module exposes:

  - `tool_nodes/0` — a list of `module | {module, opts}` describing
    every scoped action with `requires_approval: true` flagged for
    `confirm_before` actions, so the runtime factory has a single
    source of truth.
  """

  alias AshHarness.Schema.Canonical
  alias AshHarness.ToolGen

  @doc """
  Returns the AST that defines the orchestrator module. Embedded in
  the agent's DSL state via `Transformer.eval/3`.

  `has_delegates?` controls whether the per-agent
  `AshHarness.Delegation.Skill` meta-tool is appended to `tool_nodes/0`;
  it is set by the caller (`EmitTools`) from the count of
  `delegates_to` entries.
  """
  @spec quoted(
          module(),
          [Canonical.t()],
          [atom()],
          String.t() | nil,
          String.t() | nil,
          boolean()
        ) ::
          Macro.t()
  def quoted(agent_module, canonicals, confirm_before, name, _model, has_delegates? \\ false) do
    orch_mod = orchestrator_module(agent_module)
    orchestrator_name = name || agent_module |> Atom.to_string() |> String.replace("Elixir.", "")

    action_nodes =
      Enum.map(canonicals, fn %Canonical{} = c ->
        mod = ToolGen.action_module(agent_module, c)

        if c.action_name in confirm_before do
          {mod, [requires_approval: true]}
        else
          mod
        end
      end)

    delegation_nodes =
      if has_delegates?, do: [AshHarness.Delegation.Skill], else: []

    nodes_kv = action_nodes ++ [AshHarness.Harness.LoadResourceSkill] ++ delegation_nodes

    quote do
      defmodule unquote(orch_mod) do
        @moduledoc false
        use Jido.Composer.Orchestrator,
          name: unquote(orchestrator_name),
          nodes: [],
          system_prompt: nil,
          max_iterations: 25,
          ambient: [:ash_harness_session_pid, :ash_harness_session, :request_id]

        @agent unquote(agent_module)
        @nodes unquote(Macro.escape(nodes_kv))

        @doc false
        def __agent__, do: @agent

        @doc false
        def tool_nodes, do: @nodes
      end
    end
  end

  @doc """
  Returns the per-agent orchestrator module name. The orchestrator
  lives under `AshHarness.Generated.<AgentModule>.Orchestrator` so it
  doesn't appear as a child of the agent module (Elixir's nested
  `defmodule` inside a DSL eval can interact poorly with module-attribute
  state on the parent).
  """
  @spec orchestrator_module(module()) :: module()
  def orchestrator_module(agent_module),
    do: Module.concat([AshHarness.Generated, agent_module, Orchestrator])
end
