defmodule WineDiaryBot.Accounts.Profile do
  use Ecto.Schema
  # import Ecto.Changeset  <-- УБРАЛИ ИМПОРТ

  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "profiles" do
    field :display_name, :string
    field :avatar_url, :string
    field :social_links, :map
    field :is_private, :boolean, default: true

    belongs_to :user, WineDiaryBot.Accounts.User, define_field: false
    timestamps()
  end
end
