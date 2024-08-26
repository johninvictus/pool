defmodule Pooly do
  use Application

  alias Pooly.Server

  def start(_type, _args) do
    pool_config = [
      [name: "Pool1", mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 5],
      [name: "Pool2", mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 3],
      [name: "Pool3", mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 4]
    ]

    Pooly.Supervisor.start_link(pool_config)
  end

  def checkout(pool_name), do: Server.checkout(pool_name)

  def checkin(pool_name, worker_pid) do
    Server.checkin(pool_name, worker_pid)
  end

  def status(pool_name), do: Server.status(pool_name)
end
