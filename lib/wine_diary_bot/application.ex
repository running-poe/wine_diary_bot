defmodule WineDiaryBot.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("==========================================")
    Logger.info("Starting WineDiaryBot Application...")
    Logger.info("==========================================")


    children = [
      WineDiaryBot.Repo,
      WineDiaryBot.Bot.SessionManager,
      # Запускаем Handler как процесс опроса
      {WineDiaryBot.Bot.Handler, []}
      # {Telegex.Polling, [handler: WineDiaryBot.Bot.Handler]}
    ]

    opts = [strategy: :one_for_one, name: WineDiaryBot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
