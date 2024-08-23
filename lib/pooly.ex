defmodule Pooly do
  use Application
  
  alias Pooly.Server

  def start(_type, _args) do
    pool_config = [mfa: {Pooly.SampleWorker, :start_link, [[]]}, size: 5]
    Pooly.Supervisor.start_link(pool_config)
  end

  def checkout, do: Server.checkout()

  def checkin(worker_pid) do
    Server.checkin(worker_pid)
  end

  def status, do: Server.status()
end
