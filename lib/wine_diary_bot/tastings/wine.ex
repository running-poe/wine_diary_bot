defmodule WineDiaryBot.Tastings.Wine do
  use Ecto.Schema
  import Ecto.Changeset

  alias WineDiaryBot.Accounts.User
  alias WineDiaryBot.Tastings.WineType

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wines" do
    field :name, :string
    field :producer_custom, :string
    field :country_custom, :string
    field :region_custom, :string
    field :wine_type_custom, :string

    # Добавляем связь с типом вина
    belongs_to :wine_type, WineType, type: :id

    belongs_to :created_by_user, User, foreign_key: :created_by_user_id

    timestamps()
  end

  def changeset(wine, attrs) do
    wine
    |> cast(attrs, [:name, :wine_type_id, :producer_custom, :country_custom, :region_custom, :wine_type_custom])
    |> validate_required([:name])
    |> unique_constraint(:name)
    # Валидация: либо выбран тип, либо написан свой
    |> check_constraint(:wine_type_custom, name: :check_wine_type, message: "Cannot have both wine_type_id and wine_type_custom")
  end
end
