defmodule Gitmind.Card do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :integer
  schema "cards" do
    belongs_to :user, Gitmind.User
    field :fact, :string
    field :next_review_at, :utc_datetime
    field :interval, :integer, default: 1
    field :ease_factor, :float, default: 2.5
    field :repetitions, :integer, default: 0

    timestamps()
  end

  def changeset(card, attrs) do
    card
    |> cast(attrs, [:user_id, :fact, :next_review_at, :interval, :ease_factor, :repetitions])
    |> validate_required([:user_id, :fact, :next_review_at])
  end
end
