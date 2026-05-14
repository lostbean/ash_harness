defmodule AshHarness.Eval.Sandbox do
  @moduledoc """
  Per-scenario resource isolation for `AshHarness.Eval.Runner`.

  For Ash ETS-backed resources (used by tests and examples), the data
  layer keeps a private table per process under the
  `{:ash_ets_table, name, tenant}` key in the process dictionary
  (`Ash.DataLayer.Ets.private?/1`). Opening or closing the sandbox
  drops that table so each scenario sees an empty backing store.

  For AshPostgres-backed resources, sandboxing via
  `Ecto.Adapters.SQL.Sandbox.checkout/2` + rollback is a follow-up.
  v0.1.1 explicitly no-ops the postgres path; the postgres examples
  remain marked as TBD until that work lands.
  """

  alias AshHarness.Agent.Info, as: AgentInfo

  @type sandbox_handle :: %{resources: [module()]}

  @doc """
  Open a sandbox over the given list of `Ash.Resource` modules.
  Resources backed by ETS are dropped from the process's table pool
  so the scenario starts with empty state.
  """
  @spec open([module()]) :: {:ok, sandbox_handle()}
  def open(resources) when is_list(resources) do
    Enum.each(resources, &reset_resource/1)
    {:ok, %{resources: resources}}
  end

  @doc """
  Close the sandbox handle previously opened with `open/1`. Equivalent
  to another reset — useful both as bookkeeping and to make sure no
  scenario leaks state into the next one.
  """
  @spec close(sandbox_handle()) :: :ok
  def close(%{resources: resources}) do
    Enum.each(resources, &reset_resource/1)
    :ok
  end

  @doc """
  Reset (clear) state for a single resource. Public so eval scenarios
  with setup hooks can be explicit about which resources they touch.
  """
  @spec reset_resource(module()) :: :ok
  def reset_resource(resource) when is_atom(resource) do
    cond do
      ets_backed?(resource) -> reset_ets_resource(resource)
      postgres_backed?(resource) -> :ok
      true -> :ok
    end
  end

  @doc """
  Convenience helper: open a sandbox spanning every resource in the
  agent's scope.
  """
  @spec open_for_agent(module()) :: {:ok, sandbox_handle()}
  def open_for_agent(agent_module) when is_atom(agent_module) do
    agent_module
    |> AgentInfo.scoped_resources()
    |> open()
  end

  # ----------------------------------------------------------------
  # ETS reset
  # ----------------------------------------------------------------

  defp reset_ets_resource(resource) do
    table_name = ets_table_name(resource)
    keys = matching_table_keys(table_name)

    Enum.each(keys, fn key ->
      case Process.get(key) do
        nil ->
          :ok

        table ->
          _ = safe_delete(table)
          Process.delete(key)
      end
    end)

    :ok
  end

  defp matching_table_keys(table_name) do
    Process.get()
    |> Enum.map(&elem(&1, 0))
    |> Enum.filter(fn
      {:ash_ets_table, ^table_name, _tenant} -> true
      _ -> false
    end)
  end

  defp safe_delete(table) do
    case table do
      %ETS.Set{} -> ETS.Set.delete(table)
      _ -> :ok
    end
  rescue
    _ -> :ok
  end

  defp ets_table_name(resource) do
    Ash.DataLayer.Ets.Info.table(resource)
  rescue
    _ -> resource
  end

  defp ets_backed?(resource) when is_atom(resource) do
    Ash.Resource.Info.data_layer(resource) == Ash.DataLayer.Ets
  rescue
    _ -> false
  end

  defp postgres_backed?(resource) when is_atom(resource) do
    layer = safe_data_layer(resource)

    is_atom(layer) and layer != nil and layer != Ash.DataLayer.Ets and
      layer
      |> Atom.to_string()
      |> String.contains?("Postgres")
  end

  defp safe_data_layer(resource) do
    Ash.Resource.Info.data_layer(resource)
  rescue
    _ -> nil
  end
end
