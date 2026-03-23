defmodule WineDiaryBot.Tastings.TastingPhoto do
  use Ecto.Schema
  import Ecto.Changeset

  alias WineDiaryBot.Tastings.Tasting

  # ВАЖНО: UUID настройки
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasting_photos" do
    field :image_url, :string
    field :is_main, :boolean, default: false

    belongs_to :tasting, Tasting

    timestamps()
  end

  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [:image_url, :is_main, :tasting_id])
    |> validate_required([:image_url, :tasting_id])
  end
end
