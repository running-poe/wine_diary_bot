defmodule WineDiaryBot.Tastings do
  import Ecto.Query, warn: false
  alias WineDiaryBot.Repo
  alias WineDiaryBot.Tastings.{Tasting, Wine, TastingPhoto, WineType}

  @doc """
  Возвращает список всех типов вин для кнопок.
  """
  def list_wine_types do
    WineType
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Возвращает список дегустаций для пользователя с предзагруженными вином и фото.
  """
  def list_tastings(user_id, limit \\ 10) do
    Tasting
    |> where(user_id: ^user_id)
    |> order_by(desc: :tasting_date)
    |> limit(^limit)
    |> preload([:wine, :photos]) # Важно: подгружаем фото
    |> Repo.all()
  end

  @doc """
  Создает или находит вино по названию.
  Принимает дополнительный параметр opts с полями :wine_type_id или :wine_type_custom.
  """
  def get_or_create_wine(name, opts \\ %{}) do
    case Repo.get_by(Wine, name: name) do
      nil ->
        # Если вина нет, создаем с переданными параметрами (тип, страна и т.д.)
        attrs = Map.merge(%{name: name}, opts)
        %Wine{}
        |> Wine.changeset(attrs)
        |> Repo.insert()

      wine ->
        {:ok, wine}
    end
  end

  @doc """
  Сохраняет дегустацию и фото в одной транзакции.
  """
  def save_tasting(attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert(:tasting, Tasting.changeset(%Tasting{}, attrs))
    |> Ecto.Multi.run(:photo, fn repo, %{tasting: tasting} ->
      case Map.get(attrs, :photo_file_id) do
        nil -> {:ok, nil}
        file_id ->
          %TastingPhoto{}
          |> TastingPhoto.changeset(%{
            tasting_id: tasting.id,
            image_url: file_id,
            is_main: true
          })
          |> repo.insert()
      end
    end)
    |> Repo.transaction()
  end
end
