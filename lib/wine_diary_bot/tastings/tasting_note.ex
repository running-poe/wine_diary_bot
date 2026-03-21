defmodule WineDiaryBot.Tastings.TastingNote do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "tasting_notes" do
    field :color_custom, :string
    field :color_intensity_custom, :string
    field :sugar_custom, :string
    field :acidity_custom, :string
    field :tannins_custom, :string
    field :alcohol_custom, :string
    field :body_custom, :string
    field :finish_custom, :string

    belongs_to :tasting, WineDiaryBot.Tastings.Tasting
    timestamps()
  end

  def changeset(note, attrs) do
    note
    |> cast(attrs, [:color_custom, :color_intensity_custom, :sugar_custom, :acidity_custom, :tannins_custom, :alcohol_custom, :body_custom, :finish_custom, :tasting_id])
  end
end
