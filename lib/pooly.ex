defmodule Pooly do
  use Application

  alias Pooly.Server

  @timeout :timer.seconds(5)

  def start(_type, _args) do
    pool_config = [
      [name: "Pool1", mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 3, max_overflow: 1],
      [name: "Pool2", mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 3, max_overflow: 0],
      [name: "Pool3", mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 4, max_overflow: 0]
    ]

    Pooly.Supervisor.start_link(pool_config)
  end

  def checkout(pool_name, block \\ true, timeout \\ @timeout) do
    Server.checkout(pool_name, block, timeout)
  end
  

  def checkin(pool_name, worker_pid) do
    Server.checkin(pool_name, worker_pid)
  end

  def status(pool_name), do: Server.status(pool_name)
end
