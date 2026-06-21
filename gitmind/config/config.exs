import Config

config :gitmind,
  ecto_repos: [Gitmind.Repo]

# Configure Gemini & Discord key fallbacks at runtime
config :gitmind,
  gemini_api_key: System.get_env("GEMINI_API_KEY"),
  discord_bot_token: System.get_env("DISCORD_BOT_TOKEN")
