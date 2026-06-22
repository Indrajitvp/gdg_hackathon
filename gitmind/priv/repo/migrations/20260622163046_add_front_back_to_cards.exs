defmodule Gitmind.Repo.Migrations.AddFrontBackToCards do
  use Ecto.Migration

  def change do
    execute("DELETE FROM cards;")
    
    alter table(:cards) do
      remove :fact
      add :front, :text, null: false
      add :back, :text, null: false
    end
  end
end
