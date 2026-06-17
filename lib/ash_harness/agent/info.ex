defmodule AshHarness.Agent.Info do
  @moduledoc """
  Introspection for modules that `use AshHarness.Agent`. All functions
  accept either an agent module or its Spark DSL state.
  """

  alias AshHarness.Agent.Behavior.Strategy
  alias AshHarness.Agent.Delegation.DelegateEntry
  alias AshHarness.Agent.Scope.ResourceEntry

  # ----------------------------------------------------------------
  # identity
  # ----------------------------------------------------------------

  @doc "The agent's name."
  @spec name(module() | map()) :: String.t() | nil
  def name(agent), do: opt(agent, [:identity], :name)

  @doc "The agent's description."
  @spec description(module() | map()) :: String.t() | nil
  def description(agent), do: opt(agent, [:identity], :description)

  @doc "The agent's actor (struct, 0-arity function, or MFA tuple)."
  @spec actor(module() | map()) :: any()
  def actor(agent), do: opt(agent, [:identity], :actor)

  @doc "The agent's declared model identifier, or `nil`."
  @spec model(module() | map()) :: String.t() | nil
  def model(agent), do: opt(agent, [:identity], :model)

  # ----------------------------------------------------------------
  # domains
  # ----------------------------------------------------------------

  @doc "The Ash domain modules listed in the agent's `domains:` option."
  @spec domains(module() | map()) :: [module()]
  def domains(agent) do
    if spark_dsl?(agent) do
      Spark.Dsl.Extension.get_persisted(agent, :ash_harness_domains, [])
    else
      []
    end
  end

  # ----------------------------------------------------------------
  # scope
  # ----------------------------------------------------------------

  @doc "The agent's `scope` entries as `%ResourceEntry{}` structs."
  @spec scope_entries(module() | map()) :: [ResourceEntry.t()]
  def scope_entries(agent) do
    if spark_dsl?(agent) do
      agent
      |> Spark.Dsl.Extension.get_entities([:scope])
      |> Enum.filter(&match?(%ResourceEntry{}, &1))
    else
      []
    end
  end

  @doc "The list of resource modules in scope."
  @spec scoped_resources(module() | map()) :: [module()]
  def scoped_resources(agent) do
    Enum.map(scope_entries(agent), & &1.module)
  end

  @doc "The list of actions in scope for `resource`."
  @spec scoped_actions(module() | map(), module()) :: [atom()]
  def scoped_actions(agent, resource) do
    case Enum.find(scope_entries(agent), fn entry -> entry.module == resource end) do
      nil -> []
      %ResourceEntry{actions: actions} -> actions
    end
  end

  @doc "Returns `true` if `(resource, action)` is in scope for the agent."
  @spec in_scope?(module() | map(), module(), atom()) :: boolean()
  def in_scope?(agent, resource, action) when is_atom(action) do
    action in scoped_actions(agent, resource)
  end

  # ----------------------------------------------------------------
  # behavior
  # ----------------------------------------------------------------

  @doc "List of action atoms that require human confirmation."
  @spec confirm_before(module() | map()) :: [atom()]
  def confirm_before(agent) do
    opt_list(agent, [:behavior], :confirm_before)
  end

  @doc "List of action atoms that auto-execute without confirmation."
  @spec auto_execute(module() | map()) :: [atom()]
  def auto_execute(agent) do
    opt_list(agent, [:behavior], :auto_execute)
  end

  @doc "Returns `true` if the action requires confirmation."
  @spec confirms_action?(module() | map(), atom()) :: boolean()
  def confirms_action?(agent, action), do: action in confirm_before(agent)

  @doc "Strategy hints declared in the agent's `behavior` section."
  @spec strategies(module() | map()) :: [Strategy.t()]
  def strategies(agent) do
    if spark_dsl?(agent) do
      agent
      |> Spark.Dsl.Extension.get_entities([:behavior])
      |> Enum.filter(&match?(%Strategy{}, &1))
    else
      []
    end
  end

  # ----------------------------------------------------------------
  # delegation
  # ----------------------------------------------------------------

  @doc "Delegate entries declared in `delegates_to`."
  @spec delegates(module() | map()) :: [DelegateEntry.t()]
  def delegates(agent) do
    if spark_dsl?(agent) do
      agent
      |> Spark.Dsl.Extension.get_entities([:delegates_to])
      |> Enum.filter(&match?(%DelegateEntry{}, &1))
    else
      []
    end
  end

  @doc "Returns `true` when the agent may delegate to `target`."
  @spec delegate_for?(module() | map(), module()) :: boolean()
  def delegate_for?(agent, target) when is_atom(target) do
    Enum.any?(delegates(agent), fn %DelegateEntry{agent_module: m} -> m == target end)
  end

  # ----------------------------------------------------------------
  # constraints
  # ----------------------------------------------------------------

  @doc "Per-turn mutation budget (default 10)."
  @spec max_mutations_per_turn(module() | map()) :: non_neg_integer()
  def max_mutations_per_turn(agent),
    do: opt(agent, [:constraints], :max_mutations_per_turn, 10)

  @doc "Max estimated tokens for the rendered initial context (default 128_000)."
  @spec max_context_tokens(module() | map()) :: non_neg_integer()
  def max_context_tokens(agent),
    do: opt(agent, [:constraints], :max_context_tokens, 128_000)

  @doc "Max repair-loop retries per (resource, action) (default 3)."
  @spec max_repair_loop_retries(module() | map()) :: non_neg_integer()
  def max_repair_loop_retries(agent),
    do: opt(agent, [:constraints], :max_repair_loop_retries, 3)

  @doc "Actions that require an LLM-supplied `reasoning` argument."
  @spec require_reasoning_for(module() | map()) :: [atom()]
  def require_reasoning_for(agent),
    do: opt_list(agent, [:constraints], :require_reasoning_for)

  @doc "Returns `true` if the action requires explicit reasoning."
  @spec reasoning_required?(module() | map(), atom()) :: boolean()
  def reasoning_required?(agent, action), do: action in require_reasoning_for(agent)

  # ----------------------------------------------------------------
  # derived (transformer-persisted)
  # ----------------------------------------------------------------

  @doc "Reachability graph computed by `ComputeReachability`."
  @spec reachability_graph(module() | map()) :: AshHarness.Reachability.graph()
  def reachability_graph(agent) do
    if spark_dsl?(agent) do
      Spark.Dsl.Extension.get_persisted(agent, :reachability_graph, %{})
    else
      %{}
    end
  end

  @doc "Canonical tool list computed by `ComputeToolSet`."
  @spec tool_list(module() | map()) :: [AshHarness.Schema.Canonical.t()]
  def tool_list(agent) do
    if spark_dsl?(agent) do
      Spark.Dsl.Extension.get_persisted(agent, :tool_list, [])
    else
      []
    end
  end

  # ----------------------------------------------------------------
  # internal helpers
  # ----------------------------------------------------------------

  defp opt(agent, path, key, default \\ nil) do
    if spark_dsl?(agent) do
      Spark.Dsl.Extension.get_opt(agent, path, key, default)
    else
      default
    end
  end

  defp opt_list(agent, path, key) do
    if spark_dsl?(agent) do
      case Spark.Dsl.Extension.get_opt(agent, path, key, []) do
        list when is_list(list) -> list
        _ -> []
      end
    else
      []
    end
  end

  defp spark_dsl?(map) when is_map(map), do: true

  defp spark_dsl?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :spark_dsl_config, 0)
  end

  defp spark_dsl?(_), do: false
end
