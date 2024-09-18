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
              name: nil,
              overflow: 0,
              max_overflow: nil
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
  def handle_call(
        :checkout,
        {from_pid, _ref},
        %{workers: workers, monitors: monitors, worker_sup: sup, mfa: mfa} = state
      ) do
    case workers do
      [worker | rest] ->
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {worker, ref})
        {:reply, worker, %{state | workers: rest}}

      [] when state.max_overflow > 0 and state.overflow < state.max_overflow ->
        [new_worker] = start_worker_sup(sup, mfa, 1)
        ref = Process.monitor(from_pid)
        true = :ets.insert(monitors, {new_worker, ref})

        {:reply, new_worker, %{state | overflow: state.overflow + 1}}

      [] ->
        {:reply, :full, state}
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

        new_state = handle_checkin(pid, state)

        {:noreply, new_state}

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
  def handle_info({:EXIT, pid, _reason}, %{monitors: monitors} = state) do
    case :ets.lookup(monitors, pid) do
      [{pid, _ref}] ->
        new_state = handle_worker_exit(state)
        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
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

  defp handle_checkin(pid, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      overflow: overflow
    } = state

    if overflow > 0 do
      :ok = dismiss_worker(worker_sup, pid)
      %{state | overflow: overflow - 1}
    else
      %{state | overflow: 0, workers: [pid | workers]}
    end
  end

  defp handle_worker_exit(state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      overflow: overflow,
      mfa: mfa
    } = state

    if overflow > 0 do
      %{state | overflow: overflow - 1}
    else
      [new_worker] = start_worker_sup(worker_sup, mfa, 1)
      %{state | workers: [new_worker | workers]}
    end
  end

  defp dismiss_worker(sup, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(sup, pid)
  end
end
