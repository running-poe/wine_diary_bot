defmodule WineDiaryBot.Tastings.TastingPhoto do
  use Ecto.Schema
  # import Ecto.Changeset <-- УБРАЛИ ИМПОРТ

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasting_photos" do
    field :image_url, :string
    field :is_main, :boolean, default: false

    belongs_to :tasting, WineDiaryBot.Tastings.Tasting
    timestamps()
  end
end
