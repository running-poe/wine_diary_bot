defmodule WineDiaryBot.Accounts do
  import Ecto.Query, warn: false
  alias WineDiaryBot.Repo
  alias WineDiaryBot.Accounts.User

  @doc """
  Получает пользователя по telegram_id или создает нового.
  Всегда возвращает {:ok, user} или {:error, changeset}.
  """
  def get_or_create_user(telegram_id) do
    case Repo.get_by(User, telegram_id: telegram_id) do
      nil ->
        # Пользователь не найден, создаем нового
        %User{telegram_id: telegram_id}
        |> Repo.insert()

      user ->
        # Пользователь найден, оборачиваем в {:ok, ...} для единообразия
        {:ok, user}
    end
  end
end
