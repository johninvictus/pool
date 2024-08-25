defmodule Pooly.Server do
  @moduledoc false

  use GenServer

  ## API
  def start_link([pool_conf]) do
    GenServer.start_link(__MODULE__, pool_conf, name: __MODULE__)
  end

  def checkout(pool_name) do
    GenServer.call(:"#{pool_name}Server", :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(:"#{pool_name}Server", {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(:"#{pool_name}Server", :status)
  end

  ## callbacks

  @impl true
  def init(pool_conf) do
    {:ok, pool_conf, {:continue, :start_pool}}
  end

  @impl true
  def handle_continue(:start_pool, state) do
    Enum.each(state, fn pool_config ->
      {:ok, _sup} = Supervisor.start_child(Pooly.PoolsSupervisor, supervisor_spec(pool_config))
    end)

    {:noreply, state}
  end

  ## private

  defp supervisor_spec(pool_config) do
    Supervisor.child_spec({Pooly.PoolSupervisor, [pool_config]}, id: "#{pool_config[:name]}")
  end
end
