defmodule Gitmind.Repo.Migrations.CreateUsersAndCards do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :bigint, primary_key: true
      add :timezone, :string, default: "UTC", null: false

      timestamps()
    end

    create table(:cards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :bigint, on_delete: :delete_all), null: false
      add :fact, :text, null: false
      add :next_review_at, :utc_datetime, null: false
      add :interval, :integer, default: 1, null: false
      add :ease_factor, :float, default: 2.5, null: false
      add :repetitions, :integer, default: 0, null: false

      timestamps()
    end

    create index(:cards, [:next_review_at])
    create index(:cards, [:user_id])
  end
end
