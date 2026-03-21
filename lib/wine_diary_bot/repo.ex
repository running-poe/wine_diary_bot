defmodule WineDiaryBot.Repo do
  use Ecto.Repo,
    otp_app: :wine_diary_bot,
    adapter: Ecto.Adapters.Postgres
end
