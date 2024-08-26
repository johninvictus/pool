defmodule Pooly.PoolServer do
  @moduledoc false
  use GenServer
  alias Pooly.WorkerSupervisor

  defmodule State do
    defstruct pool_sup: nil,
              worker_sup: nil,
              mfa: nil,
              size: nil,
              workers: nil,
              monitors: nil,
              name: nil
  end

  ## API
  def start_link([pool_sup, pool_conf]) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_conf], name: name(pool_conf[:name]))
  end

  def checkout(pool_name) do
    GenServer.call(name(pool_name), :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

  ## callbacks

  @impl true
  def init([pool_sup, pool_conf]) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])

    state =
      Enum.reduce(pool_conf, %State{pool_sup: pool_sup, monitors: monitors}, fn {key, value},
                                                                                acc ->
        Map.put(acc, key, value)
      end)

    {:ok, state, {:continue, :start_worker_supervisor}}
  end

  @impl true
  def handle_continue(
        :start_worker_supervisor,
        %{pool_sup: sup, size: size, mfa: mfa, name: name} = state
      ) do
    {:ok, worker_sup} = Supervisor.start_child(sup, worker_supervisor_spec(name))
    workers = start_worker_sup(worker_sup, mfa, size)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  @impl true
  def handle_call(:checkout, {from_pid, _ref}, %{workers: workers, monitors: monitors} = state) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] ->
        {:reply, :noproc, state}
    end
  end

  @impl true
  def handle_call(:status, _from, %{monitors: monitors, workers: workers} = state) do
    {:reply, {length(workers), :ets.info(monitors, :size)}, state}
  end

  @impl true
  def handle_cast({:checkin, worker_pid}, %{monitors: monitors, workers: workers} = state) do
    case :ets.lookup(monitors, worker_pid) do
      [{pid, ref}] ->
        true = Process.demonitor(ref)
        true = :ets.delete(monitors, worker_pid)

        {:noreply, %{state | workers: [pid | workers]}}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, ref, _type, _object, _reason},
        %{monitors: monitors, workers: workers} = state
      ) do
    case :ets.match(monitors, {:"$1", ref}) do
      [{pid}] ->
        true = Process.demonitor(pid)
        true = :ets.delete(monitors, pid)

        new_state = %{state | workers: [pid | workers]}

        {:noreply, new_state}

      [] ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:EXIT, worker_sup, reason}, %{worker_sup: worker_sup} = state) do
    {:stop, reason, state}
  end

  @impl true
  def handle_info(
        {:EXIT, _pid, _reason},
        %{workers: workers, pool_sup: sup, mfa: mfa} = state
      ) do
    [new_worker] = start_worker_sup(sup, mfa, 1)
    new_state = %{state | workers: [new_worker | workers]}

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end

  ## private

  defp name(pool_name) do
    :"#{pool_name}Server"
  end

  defp worker_supervisor_spec(name) do
    Supervisor.child_spec({WorkerSupervisor, [self()]},
      id: "#{name}WorkerSupervisor",
      restart: :temporary
    )
  end

  defp start_worker_sup(worker_sup, mfa, size) do
    Enum.map(1..size, fn _ ->
      {:ok, worker} = WorkerSupervisor.start_child(worker_sup, mfa)
      true = Process.link(worker)
      worker
    end)
  end
end
