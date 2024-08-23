defmodule Pooly.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(pool_config) do
    Supervisor.start_link(__MODULE__, pool_config)
  end

  @impl true
  def init(pool_config) do
    Process.register(self(), :supervisor)

    children = [
      {Pooly.Server, [self(), pool_config]}
    ]

    opts = [strategy: :one_for_all]

    Supervisor.init(children, opts)
  end
end
