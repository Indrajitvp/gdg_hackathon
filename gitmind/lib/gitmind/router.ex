defmodule Gitmind.Router do
  use Plug.Router
  import Ecto.Query

  alias Gitmind.{Repo, Card, DiscordClient}

  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :dispatch

  # Health check endpoint — monitored by UptimeRobot to keep Render container alive
  get "/health" do
    body = Jason.encode!(%{
      status: "ok",
      service: "Synapse Discord Bot",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, body)
  end

  head "/health" do
    send_resp(conn, 200, "")
  end

  # Root fallback
  get "/" do
    send_resp(conn, 200, "Synapse is running.")
  end

  head "/" do
    send_resp(conn, 200, "")
  end

  # Daily/Hourly Cron trigger from Supabase pg_cron
  post "/api/internal/daily-cron" do
    cron_secret = System.get_env("CRON_SECRET")
    auth_header = Plug.Conn.get_req_header(conn, "authorization") |> List.first()

    cond do
      is_binary(cron_secret) and cron_secret != "" and auth_header != "Bearer #{cron_secret}" ->
        send_resp(conn, 401, "Unauthorized")

      true ->
        now = DateTime.utc_now()

        # Query all active due cards
        query = from(c in Card, where: c.next_review_at <= ^now)
        due_cards = Repo.all(query)

        # Send each due card to its respective user concurrently via Discord DMs
        due_cards
        |> Task.async_stream(
          fn card ->
            DiscordClient.send_review_card_to_user(card.user_id, card.id, card.front)
          end,
          max_concurrency: 5,
          on_timeout: :kill_task
        )
        |> Stream.run()

        IO.puts("Triggered reviews for #{length(due_cards)} cards.")
        send_resp(conn, 200, "Triggered reviews for #{length(due_cards)} cards.")
    end
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
