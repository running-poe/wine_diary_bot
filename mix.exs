defmodule WineDiaryBot.MixProject do
  use Mix.Project

  def project do
    [
      app: :wine_diary_bot,
      version: "0.1.0",
      elixir: "~> 1.16",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {WineDiaryBot.Application, []}
    ]
  end

  defp deps do
    [
      # База данных
      {:ecto_sql, "~> 3.10"},
      {:postgrex, ">= 0.0.0"},

      # Telegex (Фиксируем версию 1.7.2)
      {:telegex, "~> 1.7"},

      # Явные зависимости для совместимости
      {:plug, "~> 1.14"},
      {:telemetry, "~> 1.0"},

      # Утилиты
      {:mogrify, "~> 0.9"},
      {:req, "~> 0.4"},
      {:jason, "~> 1.4"},
      {:dotenvy, "~> 0.8"}
    ]
  end
end
