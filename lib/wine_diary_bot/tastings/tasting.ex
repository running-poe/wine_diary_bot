defmodule WineDiaryBot.Tastings.Tasting do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tastings" do
    field :tasting_date, :date
    field :vintage, :integer
    field :rating, :decimal
    field :purchase_price, :decimal
    field :purchase_place, :string
    field :general_comment, :string

    belongs_to :user, WineDiaryBot.Accounts.User
    belongs_to :wine, WineDiaryBot.Wines.Wine
    has_one :note, WineDiaryBot.Tastings.TastingNote
    has_many :photos, WineDiaryBot.Tastings.TastingPhoto

    timestamps()
  end

  def changeset(tasting, attrs) do
    tasting
    |> cast(attrs, [:tasting_date, :vintage, :rating, :purchase_price, :purchase_place, :general_comment, :user_id, :wine_id])
    |> validate_required([:tasting_date, :user_id, :wine_id])
  end
end
