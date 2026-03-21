defmodule WineDiaryBot.Wines.Wine do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "wines" do
    field :name, :string
    field :producer_custom, :string
    field :country_custom, :string
    field :region_custom, :string
    field :wine_type_custom, :string

    has_many :tastings, WineDiaryBot.Tastings.Tasting
    timestamps()
  end

  def changeset(wine, attrs) do
    wine
    |> cast(attrs, [:name, :producer_custom, :country_custom, :region_custom, :wine_type_custom])
    |> validate_required([:name])
  end
end
