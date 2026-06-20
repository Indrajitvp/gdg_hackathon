defmodule Gitmind.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Setup Plug HTTP Server on port 4000
      {Plug.Cowboy, scheme: :http, plug: Gitmind.Router, options: [port: 4000]}
      
      # Person B: We will add the GitManager GenServer here later to handle concurrent Git writes
    ]

    opts = [strategy: :one_for_one, name: Gitmind.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
