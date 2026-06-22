defmodule Gitmind.MixProject do
  use Mix.Project

  def project do
    [
      app: :gitmind,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Gitmind.Application, []}
    ]
  end

  defp deps do
    [
      # The dependencies we discussed in the plan
      {:plug_cowboy, "~> 2.6"}, # For the HTTP Webhook Server
      {:finch, "~> 0.16.0"},    # Pinned for Elixir 1.14
      {:req, "~> 0.4.0"},       # For making API calls to Gemini/Telegram
      {:jason, "~> 1.4"},       # For parsing JSON
      {:ecto_sql, "~> 3.10"},   # Database wrapper
      {:postgrex, "0.17.5"},    # Postgres driver (pinned for Elixir 1.14)
      {:websockex, "~> 0.4.3"}  # Discord Gateway WebSocket connection
    ]
  end
end
