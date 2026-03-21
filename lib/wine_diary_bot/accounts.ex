defmodule WineDiaryBot.Accounts do
  alias WineDiaryBot.Repo
  alias WineDiaryBot.Accounts.User
  require Logger

  def get_or_create_user(telegram_id) do
    case Repo.get_by(User, telegram_id: telegram_id) do
      nil ->
        Logger.info("Creating new user with telegram_id: #{telegram_id}")
        %User{telegram_id: telegram_id}
        |> Repo.insert!()
      user ->
        Logger.debug("Found existing user: #{user.id}")
        user
    end
  end
end
