import Config


config :dotenvy, path: ".env"

config :wine_diary_bot, WineDiaryBot.Repo,
  adapter: Ecto.Adapters.Postgres,
  # ИСПРАВЛЕНО: Объединяем ssl и ssl_opts в один параметр
  ssl: [verify: :verify_none],
  pool_size: 10

config :wine_diary_bot, :telegram, token: nil
config :wine_diary_bot, :supabase, base_url: nil, service_key: nil

import_config "#{config_env()}.exs"
