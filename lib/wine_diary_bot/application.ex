defmodule WineDiaryBot.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      WineDiaryBot.Repo,
      # 1. Хранилище состояния бота (Handler)
      {WineDiaryBot.Bot.Handler, []},
      # 2. Модуль опроса Telegram (UpdatesConsumer)
      {WineDiaryBot.Bot.Handler.UpdatesConsumer, []}
    ]

    opts = [strategy: :one_for_one, name: WineDiaryBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
