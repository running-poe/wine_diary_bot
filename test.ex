token = Application.get_env(:telegex, :token)
IO.puts("Токен в конфиге: #{inspect(token)}")

# 2. Делаем запрос через встроенный клиент Telegex
# Метод get_me/0 автоматически использует токен из конфига
case Telegex.Bot.get_me() do
  {:ok, %Telegex.Model.User{} = user} ->
    IO.puts("✅ Токен РАБОЧИЙ!")
    IO.puts("Бот: #{user.username}")

  {:error, %Telegex.Error{error_code: 404}} ->
    IO.puts("❌ Токен НЕВЕРНЫЙ (404 Not Found)")

  {:error, %Telegex.Error{error_code: code}} ->
    IO.puts("⚠️ Ошибка API: #{code}")

  {:error, reason} ->
    IO.puts("⚠️ Ошибка: #{inspect(reason)}")
end
