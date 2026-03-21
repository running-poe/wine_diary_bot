defmodule WineDiaryBot.Media do
  require Logger

  @bucket "tasting-photos"

  def process_and_upload(file_id) do
    Logger.info("Starting media processing for file_id: #{file_id}")

    with {:ok, file_path} <- download_telegram_file(file_id),
         {:ok, resized_path} <- resize_image(file_path),
         {:ok, public_url} <- upload_to_supabase(resized_path) do

      Logger.info("Media processing successful. URL: #{public_url}")
      File.rm(file_path)
      File.rm(resized_path)

      {:ok, public_url}
    else
      {:error, reason} ->
        Logger.error("Media processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp download_telegram_file(file_id) do
    Logger.debug("Requesting file path from Telegram API...")
    {:ok, file} = Telegex.get_file(file_id)
    url = "https://api.telegram.org/file/bot#{Telegex.token()}/#{file.file_path}"

    temp_path = Path.join(System.tmp_dir!(), "telegram_#{file_id}.jpg")

    case Req.get(url, into: File.stream!(temp_path)) do
      {:ok, _} ->
        Logger.debug("File downloaded successfully to temp path")
        {:ok, temp_path}
      {:error, reason} ->
        Logger.error("Failed to download file from Telegram: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp resize_image(input_path) do
    output_path = String.replace(input_path, ".jpg", "_resized.jpg")

    Logger.debug("Resizing image to 320px width...")

    input_path
    |> Mogrify.open()
    |> Mogrify.resize("320x320>")
    |> Mogrify.save(path: output_path)

    {:ok, output_path}
  end

  defp upload_to_supabase(file_path) do
    config = Application.get_env(:wine_diary_bot, :supabase)
    base_url = config[:base_url]
    service_key = config[:service_key]

    file_name = Path.basename(file_path)
    url = "#{base_url}/storage/v1/object/#{@bucket}/#{file_name}"

    Logger.debug("Uploading to Supabase Storage: #{url}")

    headers = [
      {"Authorization", "Bearer #{service_key}"},
      {"Content-Type", "image/jpeg"},
      {"x-upsert", "true"}
    ]

    case File.read(file_path) do
      {:ok, binary} ->
        case Req.post(url, headers: headers, body: binary) do
          {:ok, %{status: 200}} ->
            public_url = "#{base_url}/storage/v1/object/public/#{@bucket}/#{file_name}"
            {:ok, public_url}
          error ->
            Logger.error("Supabase upload HTTP error: #{inspect(error)}")
            {:error, :upload_failed}
        end
      {:error, reason} ->
        Logger.error("Failed to read temp file: #{inspect(reason)}")
        {:error, reason}
    end
  end
end
