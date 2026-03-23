defmodule WineDiaryBot.Tastings.Tasting do
  use Ecto.Schema
  import Ecto.Changeset

  alias WineDiaryBot.Tastings.{TastingPhoto, Wine}
  alias WineDiaryBot.Accounts.User

  # ВАЖНО: UUID настройки
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tastings" do
    field :general_comment, :string
    field :purchase_place, :string
    field :purchase_price, :decimal
    field :rating, :decimal
    field :tasting_date, :date
    field :vintage, :integer

    belongs_to :user, User
    belongs_to :wine, Wine

    has_many :photos, TastingPhoto, on_replace: :delete

    timestamps()
  end

  def changeset(tasting, attrs) do
    tasting
    |> cast(attrs, [
      :user_id,
      :wine_id,
      :tasting_date,
      :vintage,
      :rating,
      :purchase_price,
      :purchase_place,
      :general_comment
    ])
    |> validate_required([:user_id, :wine_id, :tasting_date])
    |> validate_number(:rating, greater_than_or_equal_to: 0, less_than_or_equal_to: 10)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:wine_id)
  end
end
