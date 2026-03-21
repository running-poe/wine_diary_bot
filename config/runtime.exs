import Config

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise "environment variable DATABASE_URL is missing."

  telegram_token =
    System.get_env("TELEGRAM_BOT_TOKEN") ||
      raise "environment variable TELEGRAM_BOT_TOKEN is missing."

  # ИСПРАВЛЕНИЕ: Добавляем mode: :polling
  config :telegex,
    token: telegram_token,
    mode: :polling

  supabase_url = System.get_env("SUPABASE_URL") || raise "SUPABASE_URL missing"
  supabase_key = System.get_env("SUPABASE_SERVICE_KEY") || raise "SUPABASE_SERVICE_KEY missing"

  config :wine_diary_bot, :supabase,
    base_url: supabase_url,
    service_key: supabase_key

  config :wine_diary_bot, WineDiaryBot.Repo,
    url: database_url,
    ssl: [verify: :verify_none],
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10")

  log_level = System.get_env("LOG_LEVEL") || "info"
  config :logger, level: String.to_atom(log_level)
end
