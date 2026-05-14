defmodule AshHarness.Harness.ActionExecutor do
  @moduledoc """
  Dispatches an `%Intent{}` to the right Ash entry point based on the
  action type. Loads records by id for `:update` and `:destroy`.

  Wraps Ash exceptions:
    * `Ash.Error.Forbidden` → `{:error, {:policy_denied, error}}`
    * `Ash.Error.Invalid` → `{:error, {:validation_failed, error}}`
    * everything else passes through.
  """

  alias AshHarness.Harness.Intent

  @spec run(any(), Intent.t()) :: {:ok, any()} | {:error, term()}
  def run(actor, %Intent{} = intent) do
    type = action_type(intent.resource, intent.action)
    do_run(type, actor, intent)
  rescue
    e in [Ash.Error.Forbidden] -> {:error, {:policy_denied, e}}
    e in [Ash.Error.Invalid] -> {:error, {:validation_failed, e}}
  end

  defp action_type(resource, action_name) do
    case Ash.Resource.Info.action(resource, action_name) do
      %{type: t} -> t
      _ -> :unknown
    end
  end

  defp do_run(:read, actor, %Intent{resource: resource, action: action_name, input: input}) do
    query = Ash.Query.for_read(resource, action_name, input || %{}, actor: actor)

    case Ash.read(query) do
      {:ok, records} -> {:ok, records}
      {:error, error} -> wrap_error(error)
    end
  end

  defp do_run(:create, actor, %Intent{resource: resource, action: action_name, input: input}) do
    resource
    |> Ash.Changeset.for_create(action_name, input || %{}, actor: actor)
    |> Ash.create()
    |> case do
      {:ok, record} -> {:ok, record}
      {:error, error} -> wrap_error(error)
    end
  end

  defp do_run(:update, actor, %Intent{resource: resource, action: action_name, input: input}) do
    {id, attrs} = Map.pop(input || %{}, :id)
    id = id || Map.get(input || %{}, "id")

    if is_nil(id) do
      {:error, :missing_id}
    else
      case Ash.get(resource, id, actor: actor) do
        {:ok, record} ->
          record
          |> Ash.Changeset.for_update(action_name, attrs, actor: actor)
          |> Ash.update()
          |> case do
            {:ok, updated} -> {:ok, updated}
            {:error, error} -> wrap_error(error)
          end

        {:error, error} ->
          wrap_error(error)
      end
    end
  end

  defp do_run(:destroy, actor, %Intent{resource: resource, action: action_name, input: input}) do
    id = Map.get(input || %{}, :id) || Map.get(input || %{}, "id")

    if is_nil(id) do
      {:error, :missing_id}
    else
      case Ash.get(resource, id, actor: actor) do
        {:ok, record} ->
          record
          |> Ash.Changeset.for_destroy(action_name, %{}, actor: actor)
          |> Ash.destroy()
          |> case do
            :ok -> {:ok, %{destroyed: true, id: id}}
            {:ok, _} -> {:ok, %{destroyed: true, id: id}}
            {:error, error} -> wrap_error(error)
          end

        {:error, error} ->
          wrap_error(error)
      end
    end
  end

  defp do_run(:action, actor, %Intent{resource: resource, action: action_name, input: input}) do
    case Ash.ActionInput.for_action(resource, action_name, input || %{}, actor: actor)
         |> Ash.run_action() do
      {:ok, result} -> {:ok, result}
      {:error, error} -> wrap_error(error)
    end
  end

  defp do_run(_, _actor, %Intent{action: action_name}) do
    {:error, {:unknown_action_type, action_name}}
  end

  defp wrap_error(%Ash.Error.Forbidden{} = e), do: {:error, {:policy_denied, e}}
  defp wrap_error(%Ash.Error.Invalid{} = e), do: {:error, {:validation_failed, e}}
  defp wrap_error(error), do: {:error, error}
end
