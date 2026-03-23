defmodule WineDiaryBot.Tastings.WineType do
  use Ecto.Schema

  # ВАЖНО: ID справочников у нас smallserial (целые числа)
  @primary_key {:id, :id, autogenerate: true}

  schema "ref_wine_types" do
    field :name, :string
    field :inserted_at, :naive_datetime
    field :updated_at, :naive_datetime
  end
end
 