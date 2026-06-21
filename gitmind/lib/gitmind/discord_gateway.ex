defmodule Gitmind.DiscordGateway do
  use WebSockex
  require Logger

  alias Gitmind.{Repo, User, Card, ReviewEngine, GeminiClient, DiscordClient}

  @gateway_url "wss://gateway.discord.gg/?v=10&encoding=json"

  def start_link(_opts \\ []) do
    token = Application.get_env(:gitmind, :discord_bot_token) || System.get_env("DISCORD_BOT_TOKEN")

    if is_nil(token) or token == "" do
      Logger.error("DISCORD_BOT_TOKEN is not set. Discord Gateway will not start.")
      :ignore
    else
      state = %{
        token: token,
        sequence: nil,
        heartbeat_timer: nil,
        heartbeat_interval: nil
      }
      
      WebSockex.start_link(@gateway_url, __MODULE__, state, name: __MODULE__)
    end
  end

  # WebSockex Callbacks

  @impl true
  def handle_connect(_conn, state) do
    Logger.info("Connected to Discord Gateway WebSocket.")
    {:ok, state}
  end

  @impl true
  def handle_disconnect(_conn, state) do
    Logger.warning("Disconnected from Discord Gateway. Attempting reconnect...")
    
    if state.heartbeat_timer do
      Process.cancel_timer(state.heartbeat_timer)
    end
    
    {:ok, %{state | heartbeat_timer: nil, heartbeat_interval: nil}}
  end

  @impl true
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, payload} ->
        new_seq = Map.get(payload, "s", state.sequence)
        state = %{state | sequence: new_seq}

        handle_payload(payload["op"], payload["t"], payload["d"], state)

      _ ->
        {:ok, state}
    end
  end

  # OP 10: Hello (Sent by Discord on connection startup)
  defp handle_payload(10, _event, data, state) do
    interval = data["heartbeat_interval"]
    Logger.info("Received Hello from Discord. Heartbeat interval: #{interval}ms")

    timer = schedule_heartbeat(interval)
    
    identify_payload = %{
      "op" => 2,
      "d" => %{
        "token" => "Bot #{state.token}",
        # Intents: Guild Messages (512) + Direct Messages (4096) + Message Content (32768) = 37376
        "intents" => 37376,
        "properties" => %{
          "os" => "windows",
          "browser" => "websockex",
          "device" => "websockex"
        }
      }
    }

    case WebSockex.send_frame(self(), {:text, Jason.encode!(identify_payload)}) do
      :ok ->
        {:ok, %{state | heartbeat_interval: interval, heartbeat_timer: timer}}
      error ->
        Logger.error("Failed to send identify payload: #{inspect(error)}")
        {:ok, state}
      end
  end

  # OP 0: Dispatch (Standard Discord Events)
  defp handle_payload(0, "READY", _data, state) do
    Logger.info("Discord Bot is READY and online!")
    {:ok, state}
  end

  # Filter out messages sent by bots (including ourselves)
  defp handle_payload(0, "MESSAGE_CREATE", %{"author" => %{"bot" => true}}, state) do
    {:ok, state}
  end

  # Trigger fact ingestion on user text message
  defp handle_payload(0, "MESSAGE_CREATE", %{"channel_id" => channel_id, "content" => text, "author" => %{"id" => author_id}}, state) do
    Task.start(fn ->
      handle_ingestion(author_id, channel_id, text)
    end)

    {:ok, state}
  end

  # Trigger local SM-2 calculation on user button interaction
  defp handle_payload(0, "INTERACTION_CREATE", %{
         "id" => interaction_id,
         "token" => token,
         "type" => 3,
         "message" => message,
         "data" => %{"custom_id" => callback_data},
         "user" => %{"id" => user_id}
       }, state) do

    Task.start(fn ->
      handle_button_click(interaction_id, token, message, callback_data, user_id)
    end)

    {:ok, state}
  end

  # OP 11: Heartbeat ACK (Acknowledged by Discord)
  defp handle_payload(11, _event, _data, state) do
    {:ok, state}
  end

  # Catch-all
  defp handle_payload(op, event, _data, state) do
    Logger.debug("Ignored OP #{op} event: #{inspect(event)}")
    {:ok, state}
  end

  # Periodic Heartbeat dispatch
  @impl true
  def handle_info(:heartbeat, state) do
    heartbeat_payload = %{
      "op" => 1,
      "d" => state.sequence
    }

    case WebSockex.send_frame(self(), {:text, Jason.encode!(heartbeat_payload)}) do
      :ok ->
        timer = schedule_heartbeat(state.heartbeat_interval)
        {:ok, %{state | heartbeat_timer: timer}}
      error ->
        Logger.error("Failed to send heartbeat: #{inspect(error)}")
        {:close, {1006, "Heartbeat failure"}, state}
    end
  end

  # Handles text ingestion
  defp handle_ingestion(user_id_str, channel_id, text) do
    user_id = String.to_integer(user_id_str)
    
    if text && text != "" do
      ensure_user_exists(user_id)

      case GeminiClient.slice_text(text) do
        {:ok, facts} when is_list(facts) and length(facts) > 0 ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)
          next_review = DateTime.add(now, 1, :day)

          Enum.each(facts, fn fact ->
            %Card{}
            |> Card.changeset(%{
              user_id: user_id,
              fact: fact,
              next_review_at: next_review
            })
            |> Repo.insert()
          end)

          DiscordClient.send_message(channel_id, "🧠 Ingested #{length(facts)} atomic facts! Daily reviews will start tomorrow in your DMs.")

        {:ok, _} ->
          DiscordClient.send_message(channel_id, "Could not extract any learning facts from that input. Please try sending a more factual text.")

        {:error, :missing_api_key} ->
          DiscordClient.send_message(channel_id, "🔧 System error: Gemini API key is missing. Please contact administrator.")

        {:error, _reason} ->
          DiscordClient.send_message(channel_id, "Sorry, I had trouble parsing the text. Please try again.")
      end
    end
  end

  # Updates card metrics via local SM-2 and edits review UI
  defp handle_button_click(interaction_id, interaction_token, message, callback_data, user_id_str) do
    user_id = String.to_integer(user_id_str)
    original_text = message["content"]

    case String.split(callback_data, ":") do
      ["review", feedback_str, card_id] ->
        feedback =
          case feedback_str do
            "forgot" -> :forgot
            "hard" -> :hard
            "easy" -> :easy
            _ -> nil
          end

        card = Repo.get(Card, card_id)

        cond do
          is_nil(feedback) or is_nil(card) ->
            :ok

          card.user_id != user_id ->
            :ok

          true ->
            # Run SM-2
            metrics = ReviewEngine.calculate(feedback, card.interval, card.ease_factor, card.repetitions)

            card
            |> Card.changeset(metrics)
            |> Repo.update()

            feedback_display =
              case feedback do
                :forgot -> "🔴 Forgot (Interval reset to 1 day)"
                :hard -> "🟡 Hard (Next review in #{metrics.interval} days)"
                :easy -> "🟢 Easy (Next review in #{metrics.interval} days)"
              end

            DiscordClient.respond_to_interaction(
              interaction_id,
              interaction_token,
              original_text,
              "✅ Response recorded:\n*#{feedback_display}*"
            )
        end

      _ ->
        :ok
    end
  end

  defp schedule_heartbeat(nil), do: nil
  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end

  defp ensure_user_exists(user_id) do
    case Repo.get(User, user_id) do
      nil ->
        %User{}
        |> User.changeset(%{id: user_id})
        |> Repo.insert()
      _user ->
        :ok
    end
  end
end
