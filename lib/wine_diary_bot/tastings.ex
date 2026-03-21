defmodule WineDiaryBot.Tastings do
  import Ecto.Query
  alias WineDiaryBot.Repo
  alias WineDiaryBot.Tastings.{Tasting, TastingNote, TastingPhoto}
  alias WineDiaryBot.Wines.Wine
  require Logger

  def list_user_tastings(user_id, limit \\ 10) do
    Logger.debug("Fetching tastings for user_id: #{user_id}")

    from(t in Tasting,
      where: t.user_id == ^user_id,
      order_by: [desc: t.tasting_date],
      limit: ^limit,
      preload: [:wine, :photos]
    )
    |> Repo.all()
  end

  def get_tasting!(id) do
    Logger.debug("Fetching tasting details for id: #{id}")
    from(t in Tasting, where: t.id == ^id, preload: [:wine, :photos, :note])
    |> Repo.one!()
  end

  def create_full_tasting(user_id, data) do
    Logger.info("Starting DB transaction for new tasting. User: #{user_id}, Wine: #{data.wine_name}")

    Ecto.Multi.new()
    |> Ecto.Multi.run(:wine, fn repo, _ ->
      wine_attrs = %{
        name: data.wine_name,
        producer_custom: data[:producer_custom],
        country_custom: data[:country_custom],
        region_custom: data[:region_custom]
      }

      changeset = Wine.changeset(%Wine{}, wine_attrs)
      repo.insert(changeset)
    end)
    |> Ecto.Multi.insert(:tasting, fn %{wine: wine} ->
      Logger.debug("Step: Inserting Tasting for wine_id: #{wine.id}")
      tasting_attrs = %{
        user_id: user_id,
        wine_id: wine.id,
        tasting_date: data[:tasting_date] || Date.utc_today(),
        rating: data[:rating],
        vintage: data[:vintage],
        purchase_price: data[:price]
      }
      Tasting.changeset(%Tasting{}, tasting_attrs)
    end)
    |> Ecto.Multi.insert(:note, fn %{tasting: tasting} ->
      Logger.debug("Step: Inserting Notes for tasting_id: #{tasting.id}")
      notes_attrs = %{
        tasting_id: tasting.id,
        color_custom: data[:color_custom],
        color_intensity_custom: data[:color_intensity_custom],
        sugar_custom: data[:sugar_custom],
        acidity_custom: data[:acidity_custom],
        tannins_custom: data[:tannins_custom],
        body_custom: data[:body_custom],
        finish_custom: data[:finish_custom]
      }
      TastingNote.changeset(%TastingNote{}, notes_attrs)
    end)
    |> Ecto.Multi.insert(:photo, fn %{tasting: tasting} ->
      Logger.debug("Step: Inserting Photo URL")
      %TastingPhoto{}
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(:tasting_id, tasting.id)
      |> Ecto.Changeset.put_change(:image_url, data[:image_url])
      |> Ecto.Changeset.put_change(:is_main, true)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, result} ->
        Logger.info("Transaction successful! Tasting ID: #{result.tasting.id}")
        {:ok, result}
      {:error, step, changeset, _} ->
        Logger.error("Transaction failed at step: #{step}. Errors: #{inspect(changeset.errors)}")
        {:error, changeset}
    end
  end

  def update_tasting_field(tasting_id, field, value) do
    Logger.info("Updating tasting #{tasting_id}: setting #{field} to #{inspect(value)}")
    tasting = get_tasting!(tasting_id)

    if field in [:rating, :tasting_date, :vintage, :purchase_price, :general_comment] do
      tasting
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(field, value)
      |> Repo.update()
    else
      note = tasting.note || Repo.insert!(%TastingNote{tasting_id: tasting.id})
      note
      |> Ecto.Changeset.change()
      |> Ecto.Changeset.put_change(field, value)
      |> Repo.update()
    end
  end

  def update_tasting_photo(tasting_id, new_url) do
    Logger.info("Updating photo for tasting #{tasting_id}")
    from(p in TastingPhoto, where: p.tasting_id == ^tasting_id)
    |> Repo.update_all(set: [is_main: false])

    %TastingPhoto{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_change(:tasting_id, tasting_id)
    |> Ecto.Changeset.put_change(:image_url, new_url)
    |> Ecto.Changeset.put_change(:is_main, true)
    |> Repo.insert()
  end
end
