defmodule Gitmind.User do
  use Ecto.Schema
  import Ecto.Changeset

  # Telegram chat ID is a BigInt, so we use it as the primary key
  @primary_key {:id, :integer, autogenerate: false}
  schema "users" do
    field :timezone, :string, default: "UTC"

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :timezone])
    |> validate_required([:id])
  end
end
