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
              max_overflow: nil,
              waiting: nil
  end

  ## API
  def start_link([pool_sup, pool_conf]) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_conf], name: name(pool_conf[:name]))
  end

  def checkout(pool_name, block, timeout) do
    GenServer.call(name(pool_name), {:checkout, block}, timeout)
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
    waiting = :queue.new()

    state =
      Enum.reduce(
        pool_conf,
        %State{pool_sup: pool_sup, monitors: monitors, waiting: waiting},
        fn {key, value}, acc ->
          Map.put(acc, key, value)
        end
      )

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
  def handle_call({:checkout, block}, {from_pid, _ref} = from, state) do
    %{workers: workers, monitors: monitors, worker_sup: sup, mfa: mfa, waiting: waiting} = state

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

      [] when block == true ->
        ref = Process.monitor(from_pid)
        waiting = :queue.in({from, ref}, waiting)
        {:noreply, %{state | waiting: waiting}, :infinity}

      [] ->
        {:reply, :full, state}
    end
  end

  @impl true
  def handle_call(:status, _from, %{monitors: monitors, workers: workers} = state) do
    {:reply, {state_name(state), length(workers), :ets.info(monitors, :size)}, state}
  end

  @impl true
  def handle_cast({:checkin, worker_pid}, %{monitors: monitors} = state) do
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
        :ets.delete(monitors, pid)
        new_state = handle_worker_exit(pid, state)
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
      overflow: overflow,
      monitors: monitors,
      waiting: waiting
    } = state

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        true = :ets.insert(monitors, {pid, ref})
        GenServer.reply(from, pid)
        %{state | waiting: left}

      {:empty, empty} when overflow > 0 ->
        :ok = dismiss_worker(worker_sup, pid)
        %{state | overflow: overflow - 1, waiting: empty}

      {:empty, empty} ->
        %{state | overflow: 0, workers: [pid | workers], waiting: empty}
    end
  end

  defp handle_worker_exit(pid, state) do
    %{
      worker_sup: worker_sup,
      workers: workers,
      overflow: overflow,
      mfa: mfa,
      waiting: waiting,
      monitors: monitors
    } = state

    case :queue.out(waiting) do
      {{:value, {from, ref}}, left} ->
        [new_worker] = start_worker_sup(worker_sup, mfa, 1)
        true = :ets.insert(monitors, {new_worker, ref})
        GenServer.reply(from, new_worker)

        %{state | waiting: left}

      {:empty, empty} when overflow > 0 ->
        %{state | overflow: overflow - 1, waiting: empty}

      {:empty, empty} ->
        [new_worker] = start_worker_sup(worker_sup, mfa, 1)
        workers = Enum.reject(workers, &(&1 == pid))
        %{state | workers: [new_worker | workers], waiting: empty}
    end
  end

  defp dismiss_worker(sup, pid) do
    true = Process.unlink(pid)
    Supervisor.terminate_child(sup, pid)
  end

  defp state_name(%State{overflow: overflow, max_overflow: max_overflow, workers: workers})
       when overflow < 1 do
    case length(workers) == 0 do
      true ->
        if max_overflow < 1 do
          :full
        else
          :overflow
        end

      false ->
        :ready
    end
  end

  defp state_name(%State{max_overflow: max_overflow, overflow: max_overflow}) do
    :full
  end

  defp state_name(_state) do
    :overflow
  end
end
