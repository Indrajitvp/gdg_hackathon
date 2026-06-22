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
  def handle_disconnect(conn_status, state) do
    Logger.warning("Disconnected from Discord Gateway. Reason: #{inspect(conn_status)}")
    
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
        "token" => state.token,
        # Intents: Guild Messages (512) + Direct Messages (4096) + Message Content (32768) = 37376
        "intents" => 37376,
        "properties" => %{
          "os" => "windows",
          "browser" => "websockex",
          "device" => "websockex"
        }
      }
    }

    new_state = %{state | heartbeat_interval: interval, heartbeat_timer: timer}
    {:reply, {:text, Jason.encode!(identify_payload)}, new_state}
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

  # Trigger fact ingestion on user text message or show menu
  defp handle_payload(0, "MESSAGE_CREATE", %{"channel_id" => channel_id, "content" => text, "author" => %{"id" => author_id}}, state) do
    Task.start(fn ->
      user_id = String.to_integer(author_id)
      
      is_new_user = case Repo.get(User, user_id) do
        nil ->
          %User{} |> User.changeset(%{id: user_id}) |> Repo.insert()
          true
        _ ->
          false
      end

      if is_new_user do
        welcome =
          "🧠 **Hey there! I'm Synapse — your AI flashcard study buddy.**\n" <>
          "━━━━━━━━━━━━━━━━━━━━\n" <>
          "\n" <>
          "I turn your notes, articles, and study material into smart flashcards — and help you actually remember them using **Spaced Repetition**.\n" <>
          "\n" <>
          "**Here's how to get started:**\n" <>
          "\n" <>
          "1️⃣  **Paste** any notes, article, or chunk of text into this chat\n" <>
          "2️⃣  **I'll extract** the key facts and create Q&A flashcards automatically\n" <>
          "3️⃣  **Review** your cards — I'll show the question first, then the answer\n" <>
          "4️⃣  **Grade yourself** honestly — I'll schedule your next review smartly!\n" <>
          "\n" <>
          "💡 *The more you review, the smarter the scheduling gets!*\n" <>
          "━━━━━━━━━━━━━━━━━━━━"
        DiscordClient.send_message(channel_id, welcome)
      end

      cond do
        text == "!wipe" ->
          import Ecto.Query
          {count, _} = Repo.delete_all(from(c in Card, where: c.user_id == ^user_id))
          DiscordClient.send_message(channel_id, "🗑️ **Database Wiped!**\nDeleted **#{count}** flashcards. You are starting fresh!")
          
        text && String.length(text) > 20 ->
          handle_ingestion(user_id, channel_id, text)
          
        true ->
          DiscordClient.send_main_menu(channel_id)
      end
    end)

    {:ok, state}
  end

  # Trigger interaction handles
  defp handle_payload(0, "INTERACTION_CREATE", %{
         "id" => interaction_id,
         "token" => token,
         "type" => 3,
         "message" => message,
         "data" => %{"custom_id" => callback_data}
       } = data, state) do

    user_id =
      case Map.get(data, "user") || Map.get(data, "member") do
        %{"user" => %{"id" => id}} -> id
        %{"id" => id} -> id
        _ -> nil
      end

    channel_id = Map.get(data, "channel_id")

    Task.start(fn ->
      if user_id do
        cond do
          String.starts_with?(callback_data, "menu:") ->
            handle_menu_interaction(interaction_id, token, channel_id, callback_data, user_id)
          String.starts_with?(callback_data, "flip:") ->
            handle_flip_interaction(interaction_id, token, callback_data, user_id)
          true ->
            handle_button_click(interaction_id, token, message, callback_data, user_id)
        end
      end
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

    timer = schedule_heartbeat(state.heartbeat_interval)
    new_state = %{state | heartbeat_timer: timer}
    {:reply, {:text, Jason.encode!(heartbeat_payload)}, new_state}
  end

  # Handles text ingestion
  defp handle_ingestion(user_id, channel_id, text) do
    if text && text != "" do

      case GeminiClient.slice_text(text) do
        {:ok, facts} when is_list(facts) and length(facts) > 0 ->
          now = DateTime.utc_now() |> DateTime.truncate(:second)
          next_review = DateTime.add(now, 1, :day)

          Enum.each(facts, fn %{"front" => front, "back" => back} ->
            %Card{}
            |> Card.changeset(%{
              user_id: user_id,
              front: front,
              back: back,
              next_review_at: next_review
            })
            |> Repo.insert()
          end)

          DiscordClient.send_message(channel_id, "✅ **Successfully Ingested!**\n━━━━━━━━━━━━━━━━━━━━\nExtracted **#{length(facts)}** high-quality flashcards from your text.\nThey have been added to your queue!")
          DiscordClient.send_main_menu(channel_id)

        {:ok, _} ->
          DiscordClient.send_message(channel_id, "❌ **Could not extract facts.**\nPlease try sending a more factual text or complete sentences.")

        {:error, :missing_api_key} ->
          DiscordClient.send_message(channel_id, "🔧 System error: Gemini API key is missing. Please contact administrator.")

        {:error, reason} ->
          require Logger
          Logger.error("Failed to parse Gemini response: #{inspect(reason)}")
          DiscordClient.send_message(channel_id, "⚠️ **Oops! I couldn't process that text.**\n\nThis usually happens if the text is too short, doesn't contain concrete facts, or triggered Google's safety filters. Try sending a different excerpt!")

        {:error, _reason} ->
          DiscordClient.send_message(channel_id, "Sorry, I had trouble parsing the text. Please try again.")
      end
    end
  end

  # Handles card flip interaction
  defp handle_flip_interaction(interaction_id, interaction_token, callback_data, user_id_str) do
    user_id = String.to_integer(user_id_str)

    case String.split(callback_data, ":") do
      ["flip", card_id] ->
        card = Repo.get(Card, card_id)

        cond do
          is_nil(card) -> :ok
          card.user_id != user_id -> :ok
          true ->
            DiscordClient.flip_card_to_back(
              interaction_id,
              interaction_token,
              card.front,
              card.back,
              card.id
            )
        end
      _ ->
        :ok
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
              "✅ Response recorded: *#{feedback_display}*"
            )

            # Auto-fetch next card for frictionless loop
            import Ecto.Query
            now = DateTime.utc_now()
            next_query = from(c in Card, where: c.user_id == ^user_id and c.next_review_at <= ^now, limit: 1)
            
            # Since the current interaction has the channel ID in the event message, we can get it
            channel_id = message["channel_id"]

            next_cards = Repo.all(next_query)
            
            next_cards = if length(next_cards) == 0 do
              # Fallback for Hackathon: Just grab a random active card if none are strictly due!
              Repo.all(from(c in Card, where: c.user_id == ^user_id and c.id != ^card.id, order_by: fragment("RANDOM()"), limit: 1))
            else
              next_cards
            end

            case next_cards do
              [next_card] ->
                DiscordClient.send_review_card(channel_id, next_card.id, next_card.front)
              [] ->
                DiscordClient.send_message(channel_id, "🎉 **You're all caught up!** No more flashcards due for review right now.")
            end
        end

      _ ->
        :ok
    end
  end

  # Handles main menu buttons
  defp handle_menu_interaction(interaction_id, interaction_token, channel_id, callback_data, user_id_str) do
    user_id = String.to_integer(user_id_str)

    case callback_data do
      "menu:create" ->
        DiscordClient.defer_interaction(interaction_id, interaction_token)
        DiscordClient.send_message(channel_id, "**How to create cards:**\n━━━━━━━━━━━━━━━━━━━━\nJust paste your text directly into this chat! If it's a long text block, I'll extract the core facts and turn them into flashcards automatically.")

      "menu:review" ->
        import Ecto.Query
        now = DateTime.utc_now()
        
        query = from(c in Card, where: c.user_id == ^user_id and c.next_review_at <= ^now, limit: 1)
        cards = Repo.all(query)
        
        cards = if length(cards) == 0 do
          fallback_query = from(c in Card, where: c.user_id == ^user_id, order_by: fragment("RANDOM()"), limit: 1)
          Repo.all(fallback_query)
        else
          cards
        end

        if length(cards) > 0 do
          card = hd(cards)
          
          # Reply with the card, leaving the menu intact!
          DiscordClient.reply_to_interaction_with_card(interaction_id, interaction_token, card.id, card.front)
        else
          DiscordClient.defer_interaction(interaction_id, interaction_token)
          DiscordClient.send_message(channel_id, "❌ You don't have any flashcards yet! Drop some text to get started.")
        end

      "menu:stats" ->
        import Ecto.Query
        count = Repo.aggregate(from(c in Card, where: c.user_id == ^user_id), :count, :id)
        
        DiscordClient.defer_interaction(interaction_id, interaction_token)
        DiscordClient.send_message(channel_id, "📊 **Your Stats**\n━━━━━━━━━━━━━━━━━━━━\nYou have **#{count}** active flashcards in your database!")

      _ ->
        :ok
    end
  end

  defp schedule_heartbeat(nil), do: nil
  defp schedule_heartbeat(interval) do
    Process.send_after(self(), :heartbeat, interval)
  end
end
