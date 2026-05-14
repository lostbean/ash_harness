defmodule AshHarness.Harness.LoadResourceSkill do
  @moduledoc """
  Meta-tool that returns the full per-resource detail string from the
  agent's rendered context. The LLM invokes this when it wants to see
  the schema/hints/actions detail for a specific resource (the initial
  context only includes resource summaries — see ADR 0007 progressive
  disclosure).

  Receives the session via the Jido ambient context — same pattern as
  the generated per-action tools.
  """

  use Jido.Action,
    name: "load_resource_skill",
    description: "Load the full detail for a resource by short name.",
    schema: [
      resource_name: [
        type: :string,
        required: true,
        doc: "The short name of the resource (e.g. \"ticket\", \"customer\")."
      ]
    ]

  alias AshHarness.Harness.Session
  alias AshHarness.Harness.SessionAgent

  @max_resource_name_length 100

  @impl true
  def run(params, _ctx) do
    ambient_key = Jido.Composer.Context.ambient_key()
    {ambient, params} = Map.pop(params, ambient_key, %{})

    resource_name =
      params[:resource_name] || params["resource_name"] || ""

    pid = ambient[:ash_harness_session_pid]

    cond do
      not is_binary(resource_name) or resource_name == "" ->
        {:error, "load_resource_skill requires a non-empty resource_name"}

      byte_size(resource_name) > @max_resource_name_length ->
        {:error, "Unknown resource: #{String.slice(resource_name, 0, 40)}..."}

      not is_pid(pid) ->
        {:error, "load_resource_skill called without a session pid"}

      not Process.alive?(pid) ->
        {:error, "session has terminated"}

      true ->
        lookup_detail(pid, resource_name)
    end
  rescue
    e -> {:error, "load_resource_skill error: #{Exception.message(e)}"}
  end

  defp lookup_detail(pid, resource_name) do
    case SessionAgent.get_state(pid) do
      %Session{rendered_context: %{resource_details: details}} when is_map(details) ->
        match_detail(details, resource_name)

      _ ->
        {:error, "session has no rendered context"}
    end
  end

  defp match_detail(details, resource_name) do
    needle = String.downcase(resource_name)

    found =
      Enum.find_value(details, fn {key, value} ->
        if key |> to_string() |> String.downcase() |> matches?(needle), do: value, else: nil
      end)

    case found do
      detail when is_binary(detail) -> {:ok, %{detail: detail}}
      _ -> {:error, "Unknown resource: #{resource_name}"}
    end
  end

  # A user-supplied resource name "ticket" should match an internal key
  # like `:ticket` or `:"Elixir.MyApp.Ticket"` (i.e. the short module
  # tail). We accept exact key matches and short-name (last segment)
  # matches.
  defp matches?(key_str, needle) do
    key_str == needle or
      key_str |> String.split(".") |> List.last() |> String.downcase() == needle
  end
end
