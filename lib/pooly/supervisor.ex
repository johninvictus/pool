defmodule Pooly.Supervisor do
  @moduledoc false
  use Supervisor

  def start_link(pool_config) do
    Supervisor.start_link(__MODULE__, pool_config, name: __MODULE__)
  end

  @impl true
  def init(pool_config) do

    children = [
      {Pooly.Server, [pool_config]},
      {Pooly.PoolsSupervisor, []}
    ]

    opts = [strategy: :one_for_all]

    Supervisor.init(children, opts)
  end
end
