defmodule Gitmind.Repo do
  use Ecto.Repo,
    otp_app: :gitmind,
    adapter: Ecto.Adapters.Postgres

  @impl true
  def init(_type, config) do
    url = System.get_env("DATABASE_URL") || "postgres://postgres:postgres@localhost/gitmind_dev"
    
    # Auto-enable SSL if the URL matches supabase or DATABASE_SSL is explicitly set to true
    ssl? = System.get_env("DATABASE_SSL") == "true" or String.contains?(url, "supabase")

    config =
      config
      |> Keyword.put(:url, url)
      |> Keyword.put(:pool_size, String.to_integer(System.get_env("POOL_SIZE") || "10"))

    config =
      if ssl? do
        Keyword.put(config, :ssl, [verify: :verify_none])
      else
        config
      end

    {:ok, config}
  end
end
