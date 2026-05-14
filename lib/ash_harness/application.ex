defmodule AshHarness.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      AshHarness.Harness.SessionSupervisor
    ]

    opts = [strategy: :one_for_one, name: AshHarness.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
