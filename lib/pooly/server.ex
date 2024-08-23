defmodule Pooly.Server do
  @moduledoc false

  use GenServer

  alias Pooly.WorkerSupervisor

  defmodule State do
    defstruct sup: nil, worker_sup: nil, mfa: nil, size: nil, workers: nil, monitors: nil
  end

  ## API
  def start_link([supervisor, pool_conf]) do
    GenServer.start_link(__MODULE__, [supervisor, pool_conf], name: __MODULE__)
  end

  def checkout() do
    GenServer.call(__MODULE__, :checkout)
  end

  def checkin(worker_pid) do
    GenServer.cast(__MODULE__, {:checkin, worker_pid})
  end

  def status do
    GenServer.call(__MODULE__, :status)
  end

  ## callbacks

  @impl true
  def init([supervisor, pool_conf]) do
    monitors = :ets.new(:monitors, [:private])

    state =
      Enum.reduce(pool_conf, %State{sup: supervisor, monitors: monitors}, fn {key, value}, acc ->
        Map.put(acc, key, value)
      end)

    {:ok, state, {:continue, :start_worker_supervisor}}
  end

  @impl true
  def handle_continue(:start_worker_supervisor, %{sup: sup, size: size, mfa: mfa} = state) do
    {:ok, worker_sup} = Supervisor.start_child(sup, worker_supervisor_spec())
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

    {:noreply, state}
  end

  ## private

  defp worker_supervisor_spec do
    Supervisor.child_spec({WorkerSupervisor, [[]]}, id: WorkerSupervisor, restart: :temporary)
  end

  defp start_worker_sup(worker_sup, mfa, size) do
    Enum.map(1..size, fn _ ->
      {:ok, worker} = WorkerSupervisor.start_child(worker_sup, mfa)
      worker
    end)
  end
end
