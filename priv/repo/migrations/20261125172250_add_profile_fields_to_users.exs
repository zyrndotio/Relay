defmodule Relay.Repo.Migrations.AddProfileFieldsToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :username, :string
      add :display_name, :string
      add :bio, :text
      add :avatar_url, :string, null: false, default: "/images/default-avatar.png"
    end

    execute(
      """
      UPDATE users
      SET username = 'user_' || id
      WHERE username IS NULL
      """,
      """
      UPDATE users
      SET username = NULL
      """
    )

    alter table(:users) do
      modify :username, :string, null: false, from: :string
    end

    create unique_index(:users, [:username])
  end
end
