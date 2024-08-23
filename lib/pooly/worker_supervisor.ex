defmodule Pooly.WorkerSupervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  def start_child(supervisor, {m, _f, _a} = mfa) do
    DynamicSupervisor.start_child(supervisor, %{id: m, start: mfa})
  end

  @impl true
  def init(_) do
    Process.register(self(), :worker_supervisor)
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
