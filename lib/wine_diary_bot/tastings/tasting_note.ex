defmodule WineDiaryBot.Tastings.TastingNote do
  use Ecto.Schema
  import Ecto.Changeset

  alias WineDiaryBot.Tastings.Tasting

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasting_notes" do
    # Визуал
    belongs_to :color, WineDiaryBot.Tastings.Level, type: :id
    field :color_custom, :string
    belongs_to :color_intensity, WineDiaryBot.Tastings.Level, type: :id
    field :color_intensity_custom, :string

    # Аромат
    belongs_to :aroma_intensity, WineDiaryBot.Tastings.Level, type: :id
    field :aroma_intensity_custom, :string

    # Вкус
    belongs_to :taste_intensity, WineDiaryBot.Tastings.Level, type: :id
    field :taste_intensity_custom, :string

    belongs_to :sugar, WineDiaryBot.Tastings.Level, type: :id
    field :sugar_custom, :string

    belongs_to :acidity, WineDiaryBot.Tastings.Level, type: :id
    field :acidity_custom, :string

    belongs_to :tannins, WineDiaryBot.Tastings.Level, type: :id
    field :tannins_custom, :string

    # ИЗМЕНЕНО: Удаляем старые ссылки на alcohol_id, добавляем числовое поле
    field :abv, :decimal

    belongs_to :body, WineDiaryBot.Tastings.Level, type: :id
    field :body_custom, :string

    belongs_to :finish, WineDiaryBot.Tastings.Level, type: :id
    field :finish_custom, :string

    belongs_to :tasting, Tasting

    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [
      :tasting_id,
      :color_id, :color_custom,
      :color_intensity_id, :color_intensity_custom,
      :aroma_intensity_id, :aroma_intensity_custom,
      :taste_intensity_id, :taste_intensity_custom,
      :sugar_id, :sugar_custom,
      :acidity_id, :acidity_custom,
      :tannins_id, :tannins_custom,
      :abv, # Добавлено
      :body_id, :body_custom,
      :finish_id, :finish_custom
    ])
  end
end
