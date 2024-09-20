defmodule Pooly.SampleWorker do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, :ok, [])
  end

  def stop(pid) do
    GenServer.call(pid, :stop)
  end

  def work_for(pid, duration \\ :timer.seconds(5)) do
    GenServer.cast(pid, {:work_for, duration})
  end

  @impl true
  def init(_) do
    {:ok, []}
  end

  @impl true
  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_cast({:work_for, duration}, state) do
    :timer.sleep(duration)
    {:stop, :normal, state}
  end
end
