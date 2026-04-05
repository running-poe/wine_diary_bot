defmodule WineDiaryBot.Tastings.Level do
  use Ecto.Schema

  @primary_key {:id, :id, autogenerate: true}

  schema "ref_levels" do
    field :group_name, :string
    field :value, :string

    timestamps()
  end
end
