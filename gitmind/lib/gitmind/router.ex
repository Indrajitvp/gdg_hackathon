defmodule Gitmind.Router do
  use Plug.Router

  plug :match
  plug Plug.Parsers, parsers: [:json], pass: ["application/json"], json_decoder: Jason
  plug :dispatch

  get "/" do
    send_resp(conn, 200, "GitMind API is running.")
  end

  # --------------------------------------------------------
  # PERSON A (API Engineer) STARTING POINT
  # --------------------------------------------------------
  post "/api/telegram" do
    # This is where Telegram will send messages.
    # Person A will extract the text, send it to Gemini, and then pass the result to Person B's Git module.
    IO.inspect(conn.body_params, label: "Incoming Telegram Webhook")
    send_resp(conn, 200, "OK")
  end

  # --------------------------------------------------------
  # PERSON B (Engine Engineer) STARTING POINT
  # --------------------------------------------------------
  post "/api/internal/daily-cron" do
    # This is where the Supabase Cron Job will ping every day.
    # Person B will trigger the Git DB scan here to find due facts, and pass them to Person A's Telegram module to send out.
    IO.puts("Cron Job Triggered!")
    send_resp(conn, 200, "Cron Started")
  end

  match _ do
    send_resp(conn, 404, "Not Found")
  end
end
