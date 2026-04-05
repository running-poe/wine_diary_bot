defmodule WineDiaryBot.Tastings do
  import Ecto.Query, warn: false
  alias WineDiaryBot.Repo
  alias WineDiaryBot.Tastings.{Tasting, Wine, TastingPhoto, WineType, Level, Color, TastingNote}

  # ... остальные функции ...

  def list_wine_types do
    WineType |> order_by(:name) |> Repo.all()
  end

  def list_colors do
    Color |> order_by(:name) |> Repo.all()
  end

  def list_levels_by_group(group_name) do
    Level
    |> where(group_name: ^group_name)
    |> order_by(:id)
    |> Repo.all()
  end

  def get_or_create_wine(name, opts \\ %{}) do
    case Repo.get_by(Wine, name: name) do
      nil ->
        attrs = Map.merge(%{name: name}, opts)
        %Wine{}
        |> Wine.changeset(attrs)
        |> Repo.insert()

      wine -> {:ok, wine}
    end
  end

  # ИЗМЕНЕНО: Добавлен preload :note
  def list_tastings(user_id, limit \\ 10) do
    Tasting
    |> where(user_id: ^user_id)
    |> order_by(desc: :tasting_date)
    |> limit(^limit)
    |> preload([:wine, :photos, :note])
    |> Repo.all()
  end

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
    |> Ecto.Multi.run(:notes, fn repo, %{tasting: tasting} ->
      notes_attrs = Map.get(attrs, :notes, %{})
      if map_size(notes_attrs) > 0 do
        %TastingNote{tasting_id: tasting.id}
        |> TastingNote.changeset(notes_attrs)
        |> repo.insert()
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
  end
end
