defmodule Pooly.WorkerSupervisor do
  @moduledoc false
  use DynamicSupervisor

  def start_link([pool_server]) do
    DynamicSupervisor.start_link(__MODULE__, [pool_server])
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
  def init([pool_server]) do
    Process.link(pool_server)

    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 5
    )
  end
end
