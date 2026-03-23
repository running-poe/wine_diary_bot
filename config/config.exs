import Config


config :dotenvy, path: ".env"

config :wine_diary_bot, WineDiaryBot.Repo,
  adapter: Ecto.Adapters.Postgres,
  # ИСПРАВЛЕНО: Объединяем ssl и ssl_opts в один параметр
  ssl: [verify: :verify_none],
  pool_size: 15,          # Стандартно 10, увеличим для параллельных задач
  queue_target: 2000,     # Ждать соединение до 2 секунд (по умолчанию 50мс - мало для удаленной БД)
  queue_interval: 2000,
  prepare: :unnamed,
  show_sensitive_data_on_connection_error: true

config :wine_diary_bot, :telegram, token: nil
config :wine_diary_bot, :supabase, base_url: nil, service_key: nil

import_config "#{config_env()}.exs"
