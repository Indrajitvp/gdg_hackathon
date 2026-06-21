defmodule Gitmind.DiscordClient do
  require Logger

  @api_version "v10"
  @base_url "https://discord.com/api/#{@api_version}"

  @doc """
  Sends a direct text message to a user.
  """
  def send_message_to_user(user_id, text) do
    case create_dm_channel(user_id) do
      {:ok, channel_id} ->
        send_message(channel_id, text)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends a review card (fact with inline buttons) to a user via DM.
  """
  def send_review_card_to_user(user_id, card_id, fact) do
    case create_dm_channel(user_id) do
      {:ok, channel_id} ->
        send_review_card(channel_id, card_id, fact)
      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Creates a DM channel for a given User ID.
  Returns {:ok, channel_id}
  """
  def create_dm_channel(user_id) do
    url = "#{@base_url}/users/@me/channels"
    body = %{"recipient_id" => to_string(user_id)}

    case request(:post, url, body) do
      {:ok, %{"id" => channel_id}} ->
        {:ok, channel_id}
      {:error, reason} ->
        Logger.error("Failed to create DM channel for user #{user_id}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Sends a basic message to a channel.
  """
  def send_message(channel_id, text) do
    url = "#{@base_url}/channels/#{channel_id}/messages"
    body = %{"content" => text}

    case request(:post, url, body) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sends a review card with buttons (Forgot, Hard, Easy) to a channel.
  """
  def send_review_card(channel_id, card_id, fact) do
    url = "#{@base_url}/channels/#{channel_id}/messages"
    body = %{
      "content" => "🧠 **Review Fact:**\n\n#{fact}",
      "components" => [
        %{
          "type" => 1, # Action Row
          "components" => [
            %{
              "type" => 2, # Button
              "style" => 4, # Red (Danger)
              "label" => "Forgot",
              "custom_id" => "review:forgot:#{card_id}"
            },
            %{
              "type" => 2, # Button
              "style" => 2, # Grey (Secondary)
              "label" => "Hard",
              "custom_id" => "review:hard:#{card_id}"
            },
            %{
              "type" => 2, # Button
              "style" => 3, # Green (Success)
              "label" => "Easy",
              "custom_id" => "review:easy:#{card_id}"
            }
          ]
        }
      ]
    }

    case request(:post, url, body) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Responds to an interaction to edit the original message and clear buttons.
  """
  def respond_to_interaction(interaction_id, interaction_token, original_text, feedback_text) do
    url = "#{@base_url}/interactions/#{interaction_id}/#{interaction_token}/callback"
    body = %{
      "type" => 7, # UPDATE_MESSAGE
      "data" => %{
        "content" => "#{original_text}\n\n#{feedback_text}",
        "components" => [] # Empty components array deletes all buttons
      }
    }

    case request(:post, url, body) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, reason}
    end
  end

  # Helper to construct request headers and handle responses
  defp request(method, url, body) do
    token = Application.get_env(:gitmind, :discord_bot_token) || System.get_env("DISCORD_BOT_TOKEN")

    if is_nil(token) or token == "" do
      Logger.error("DISCORD_BOT_TOKEN is not set.")
      {:error, :missing_bot_token}
    else
      headers = [
        {"Authorization", "Bot #{token}"},
        {"Content-Type", "application/json"}
      ]

      options = [
        headers: headers,
        json: body
      ]

      result =
        case method do
          :post -> Req.post(url, options)
          :patch -> Req.patch(url, options)
          :get -> Req.get(url, options)
        end

      case result do
        {:ok, %Req.Response{status: status, body: res_body}} when status in 200..299 ->
          {:ok, res_body}
        {:ok, %Req.Response{status: status, body: err_body}} ->
          Logger.error("Discord API error [#{method} #{url}]. Status: #{status}, Body: #{inspect(err_body)}")
          {:error, {:discord_api_error, status, err_body}}
        {:error, exception} ->
          Logger.error("Discord connection error: #{inspect(exception)}")
          {:error, :connection_failed}
      end
    end
  end
end
