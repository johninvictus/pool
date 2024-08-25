defmodule Pooly.WorkerSupervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, [])
  end

  def start_child(supervisor, {m, _f, _a} = mfa) do
    DynamicSupervisor.start_child(supervisor, %{
      id: m,
      start: mfa,
      shutdown: 5_000,
      restart: :temporary
    })
  end

  @impl true
  def init(_) do

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 5
    )
  end
end
