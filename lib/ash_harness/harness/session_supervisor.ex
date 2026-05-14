defmodule AshHarness.Harness.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor that owns `AshHarness.Harness.SessionAgent`
  processes. One child per active session. Transient restart strategy —
  a crashed SessionAgent is not restarted automatically; the host's
  next `Harness.run/3` will observe `{:error, :session_terminated, _}`.
  """

  use DynamicSupervisor

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a SessionAgent under this supervisor with the given initial
  session state. Returns `{:ok, pid}`.
  """
  @spec start_session(AshHarness.Harness.Session.t()) :: DynamicSupervisor.on_start_child()
  def start_session(%AshHarness.Harness.Session{} = session) do
    spec = %{
      id: AshHarness.Harness.SessionAgent,
      start: {AshHarness.Harness.SessionAgent, :start_link, [[session: session]]},
      restart: :transient,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
