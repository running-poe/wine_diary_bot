defmodule WineDiaryBot.Accounts.Profile do
  use Ecto.Schema
  import Ecto.Changeset

  alias WineDiaryBot.Accounts.User

  # ВАЖНО: Primary key для profiles - это user_id (UUID), он не автогенерируемый
  @primary_key {:user_id, :binary_id, autogenerate: false}
  @foreign_key_type :binary_id

  schema "profiles" do
    field :display_name, :string
    field :avatar_url, :string
    field :social_links, :map
    field :is_private, :boolean, default: true

    # Связь с users
    belongs_to :user, User, define_field: false, foreign_key: :user_id

    timestamps()
  end

  def changeset(profile, attrs) do
    profile
    |> cast(attrs, [:user_id, :display_name, :avatar_url, :social_links, :is_private])
    |> validate_required([:user_id])
    |> unique_constraint(:user_id)
  end
end
