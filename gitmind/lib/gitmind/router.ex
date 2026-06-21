defmodule Gitmind.Router do
  use Plug.Router
  import Ecto.Query

  alias Gitmind.{Repo, Card, DiscordClient}

  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :dispatch

  # Root endpoint: Serves as a keep-alive/health check to wake up the Render container
  get "/" do
    send_resp(conn, 200, "GitMind Discord API is running.")
  end

  # Daily/Hourly Cron trigger from Supabase pg_cron
  post "/api/internal/daily-cron" do
    now = DateTime.utc_now()

    # Query all active due cards
    query = from(c in Card, where: c.next_review_at <= ^now)
    due_cards = Repo.all(query)

    # Send each due card to its respective user via Discord DMs
    Enum.each(due_cards, fn card ->
      DiscordClient.send_review_card_to_user(card.user_id, card.id, card.fact)
    end)

    IO.puts("Triggered reviews for #{length(due_cards)} cards.")
    send_resp(conn, 200, "Triggered reviews for #{length(due_cards)} cards.")
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
