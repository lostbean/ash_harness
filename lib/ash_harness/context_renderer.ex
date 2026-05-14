defmodule AshHarness.ContextRenderer do
  @moduledoc """
  Renders an agent's initial system prompt and per-resource detail
  strings. The initial text contains identity, domain vocabulary,
  per-resource summaries, traversal map, strategies, delegation hints,
  constraints, and meta-tool documentation. Per-resource detail
  (full attribute / action listings) loads on demand.

  Output is an `%AshHarness.RenderedContext{}` struct.

  ## Options

    * `:actor` — override the agent's identity actor for `Ash.can?` pre-filtering.
    * `:token_budget` — pos_integer; sections are dropped to fit within
      this budget. Order: strategies → delegation → vocabulary. Resource
      summaries are never truncated.
    * `:cache?` — defaults to `true`. Disable for fresh renders during
      development or testing.

  The renderer caches its output in an ETS table keyed by
  `{agent_module, actor_id_or_nil}`. The cache invalidates when the
  agent module's source MD5 changes.
  """

  alias AshHarness.Agent.Info, as: AgentInfo
  alias AshHarness.ContextRenderer.TokenEstimate
  alias AshHarness.Domain.Info, as: DomainInfo
  alias AshHarness.Reachability
  alias AshHarness.RenderedContext
  alias AshHarness.Resource.Info, as: ResourceInfo

  @table :ash_harness_context_cache

  @doc """
  Render an `%AshHarness.RenderedContext{}` for the given agent module.
  """
  @spec render(module(), keyword()) :: RenderedContext.t()
  def render(agent_module, opts \\ []) when is_atom(agent_module) do
    actor = Keyword.get(opts, :actor) || resolve_actor(AgentInfo.actor(agent_module))
    use_cache? = Keyword.get(opts, :cache?, true)
    cache_key = {agent_module, actor_id(actor), agent_signature(agent_module)}

    case use_cache? && cache_lookup(cache_key) do
      %RenderedContext{} = cached ->
        cached

      _ ->
        rendered = do_render(agent_module, actor, opts)

        if use_cache?, do: cache_put(cache_key, rendered)
        rendered
    end
  end

  defp do_render(agent_module, actor, opts) do
    budget = Keyword.get(opts, :token_budget)

    base_sections = build_sections(agent_module, actor)
    {sections_used, warnings} = apply_budget(base_sections, budget)

    initial_text = compose(sections_used)

    resource_details =
      agent_module
      |> AgentInfo.scoped_resources()
      |> Enum.into(%{}, fn resource ->
        {resource, render_resource(agent_module, resource, actor)}
      end)

    %RenderedContext{
      initial_text: initial_text,
      token_estimate: TokenEstimate.estimate(initial_text),
      resource_details: resource_details,
      warnings: warnings
    }
  end

  # ----------------------------------------------------------------
  # Section builders
  # ----------------------------------------------------------------

  defp build_sections(agent_module, actor) do
    [
      identity: identity_section(agent_module),
      vocabulary: vocabulary_section(agent_module),
      resources: resource_summary_section(agent_module),
      traversal: traversal_section(agent_module),
      strategies: strategy_section(agent_module),
      delegation: delegation_section(agent_module),
      constraints: constraints_section(agent_module),
      meta_tools: meta_tools_section(agent_module, actor)
    ]
  end

  defp identity_section(agent_module) do
    name = AgentInfo.name(agent_module) || "agent"
    description = AgentInfo.description(agent_module) || ""

    """
    # Identity

    Name: #{name}
    Description: #{description}
    """
  end

  defp vocabulary_section(agent_module) do
    domains = AgentInfo.domains(agent_module)
    terms = Enum.flat_map(domains, &DomainInfo.terms/1)

    if terms == [] do
      ""
    else
      lines =
        Enum.map_join(terms, "\n", fn t -> "- **#{t.word}**: #{t.definition}" end)

      "# Vocabulary\n\n" <> lines <> "\n"
    end
  end

  defp resource_summary_section(agent_module) do
    lines =
      Enum.map_join(AgentInfo.scope_entries(agent_module), "\n", fn entry ->
        resource = entry.module

        summary =
          ResourceInfo.description(resource) ||
            "Resource #{inspect(resource)}"

        action_list = Enum.map_join(entry.actions, ", ", &Atom.to_string/1)
        "- **#{inspect(resource)}** — #{summary} (actions: #{action_list})"
      end)

    "# Resources\n\n" <> lines <> "\n"
  end

  defp traversal_section(agent_module) do
    graph = AgentInfo.reachability_graph(agent_module)

    edges =
      graph
      |> Enum.flat_map(fn {_src, edges} -> edges end)
      |> Enum.map(fn edge ->
        "- #{inspect(edge.source)} -[:#{edge.relationship_name}]-> #{inspect(edge.destination)}"
      end)

    if edges == [] do
      ""
    else
      "# Traversal\n\n" <> Enum.join(edges, "\n") <> "\n"
    end
  end

  defp strategy_section(agent_module) do
    case AgentInfo.strategies(agent_module) do
      [] ->
        ""

      strategies ->
        lines =
          Enum.map_join(strategies, "\n", fn s -> "- **#{s.name}**: #{s.description}" end)

        "# Strategies\n\n" <> lines <> "\n"
    end
  end

  defp delegation_section(agent_module) do
    case AgentInfo.delegates(agent_module) do
      [] ->
        ""

      delegates ->
        lines =
          Enum.map_join(delegates, "\n", fn d ->
            "- #{inspect(d.agent_module)} — #{d.for}"
          end)

        "# Delegation\n\nYou may ask:\n\n" <> lines <> "\n"
    end
  end

  defp constraints_section(agent_module) do
    """
    # Operating Limits

    - At most #{AgentInfo.max_mutations_per_turn(agent_module)} successful mutations per turn.
    - Max context tokens: #{AgentInfo.max_context_tokens(agent_module)}.
    - Repair-loop retries per action: #{AgentInfo.max_repair_loop_retries(agent_module)}.
    """
  end

  defp meta_tools_section(agent_module, _actor) do
    base = """
    # Meta-tools

    - `load_resource_skill(resource_name)` — load the full detail for a resource
      when you need it.
    """

    if AgentInfo.delegates(agent_module) != [] do
      base <>
        "- `delegate(target, question)` — ask another agent a text question.\n"
    else
      base
    end
  end

  # ----------------------------------------------------------------
  # Per-resource detail
  # ----------------------------------------------------------------

  @doc """
  Render the detail string for one resource. Excludes hidden attributes
  and out-of-scope actions; honors `Ash.can?` pre-filtering when the
  actor is provided.
  """
  @spec render_resource(module(), module(), term() | nil) :: String.t()
  def render_resource(agent_module, resource_module, actor \\ nil) do
    desc = ResourceInfo.description(resource_module) || inspect(resource_module)
    hidden = MapSet.new(ResourceInfo.hidden_attributes(resource_module))

    attributes =
      resource_module
      |> safe_attributes()
      |> Enum.reject(fn a -> MapSet.member?(hidden, a.name) end)

    scoped_actions = AgentInfo.scoped_actions(agent_module, resource_module)

    actions =
      resource_module
      |> safe_actions()
      |> Enum.filter(fn a -> a.name in scoped_actions end)
      |> Enum.reject(fn a -> actor && policy_denies?(actor, resource_module, a) end)

    attr_lines =
      Enum.map_join(attributes, "\n", fn a -> "  - #{a.name} :: #{inspect(a.type)}" end)

    action_lines =
      Enum.map_join(actions, "\n", fn a ->
        indicators = action_indicators(agent_module, a.name)
        hint = ResourceInfo.hint_for(resource_module, a.name)

        text = "  - **#{a.name}** (type: #{a.type})#{indicators}"
        if hint, do: text <> "\n    Hint: #{hint}", else: text
      end)

    traversal =
      agent_module
      |> AgentInfo.reachability_graph()
      |> Reachability.edges_from(resource_module)
      |> Enum.map_join("\n", fn edge ->
        "  - :#{edge.relationship_name} -> #{inspect(edge.destination)}"
      end)

    """
    # #{inspect(resource_module)}

    #{desc}

    ## Attributes
    #{attr_lines}

    ## Actions in scope
    #{action_lines}

    ## Traversable relationships
    #{traversal}
    """
  end

  defp action_indicators(agent_module, action_name) do
    indicators = []

    indicators =
      if action_name in AgentInfo.auto_execute(agent_module),
        do: [" (auto-execute)" | indicators],
        else: indicators

    indicators =
      if action_name in AgentInfo.confirm_before(agent_module),
        do: [" (requires confirmation)" | indicators],
        else: indicators

    indicators =
      if action_name in AgentInfo.require_reasoning_for(agent_module),
        do: [" (requires reasoning)" | indicators],
        else: indicators

    Enum.join(indicators)
  end

  defp safe_attributes(resource) do
    if function_exported?(Ash.Resource.Info, :attributes, 1) do
      Ash.Resource.Info.attributes(resource)
    else
      []
    end
  end

  defp safe_actions(resource) do
    if function_exported?(Ash.Resource.Info, :actions, 1) do
      Ash.Resource.Info.actions(resource)
    else
      []
    end
  end

  defp policy_denies?(actor, resource, action) do
    case Ash.can?({resource, action.name}, actor) do
      false -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  # ----------------------------------------------------------------
  # Budget + composition
  # ----------------------------------------------------------------

  @droppable_order [:strategies, :delegation, :vocabulary]

  defp apply_budget(sections, nil), do: {sections, []}

  defp apply_budget(sections, budget) when is_integer(budget) and budget > 0 do
    composed = compose(sections)
    current = TokenEstimate.estimate(composed)

    if current <= budget do
      {sections, []}
    else
      drop_until_fits(sections, budget, @droppable_order, [])
    end
  end

  defp drop_until_fits(sections, _budget, [], warnings),
    do: {sections, [warning_for_overflow() | warnings]}

  defp drop_until_fits(sections, budget, [drop_key | rest], warnings) do
    new_sections = Keyword.put(sections, drop_key, "")
    composed = compose(new_sections)

    if TokenEstimate.estimate(composed) <= budget do
      {new_sections, warnings}
    else
      drop_until_fits(new_sections, budget, rest, warnings)
    end
  end

  defp warning_for_overflow do
    "rendered initial context exceeds the requested token budget; resource summaries were preserved"
  end

  defp compose(sections) when is_list(sections) do
    sections
    |> Enum.map(fn {_key, text} -> text end)
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join("\n")
  end

  # ----------------------------------------------------------------
  # Actor resolution
  # ----------------------------------------------------------------

  defp resolve_actor(actor) when is_function(actor, 0), do: actor.()

  defp resolve_actor({mod, fun, args}) when is_atom(mod) and is_atom(fun) and is_list(args),
    do: apply(mod, fun, args)

  defp resolve_actor(actor), do: actor

  defp actor_id(nil), do: nil
  defp actor_id(%{id: id}), do: id
  defp actor_id(actor), do: :erlang.phash2(actor)

  # ----------------------------------------------------------------
  # ETS cache
  # ----------------------------------------------------------------

  defp ensure_table do
    case :ets.whereis(@table) do
      :undefined ->
        :ets.new(@table, [:named_table, :public, :set])

      _ ->
        @table
    end
  end

  defp cache_lookup(key) do
    ensure_table()

    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  end

  defp cache_put(key, value) do
    ensure_table()
    :ets.insert(@table, {key, value})
    value
  end

  defp agent_signature(agent_module) do
    case :erlang.module_loaded(agent_module) do
      true ->
        agent_module.module_info(:md5)

      false ->
        if Code.ensure_loaded?(agent_module), do: agent_module.module_info(:md5), else: nil
    end
  end
end
