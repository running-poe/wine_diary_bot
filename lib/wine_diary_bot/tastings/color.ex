defmodule WineDiaryBot.Tastings.Color do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "ref_colors" do
    field :name, :string
    timestamps()
  end
end
