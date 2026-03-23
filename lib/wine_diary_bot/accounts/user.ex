defmodule WineDiaryBot.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  # ВАЖНО: Указываем, что ID это UUID (binary_id)
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :telegram_id, :integer
    field :email, :string

    has_one :profile, WineDiaryBot.Accounts.Profile

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:telegram_id, :email])
    |> validate_required([:telegram_id])
    |> unique_constraint(:telegram_id)
  end
end
