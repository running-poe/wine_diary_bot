defmodule WineDiaryBot.Bot.Handler do
  use Telegex.Polling.GenHandler

  alias WineDiaryBot.Bot.SessionManager
  alias WineDiaryBot.Tastings
  alias WineDiaryBot.Accounts
  require Logger

   defstruct offset: 0, limit: 100, timeout: 60, interval: 1000, allowed_updates: []

  @org_steps [
    {:color, nil, :color_custom},
    {:color_intensity, "intensity", :color_intensity_custom},
    {:sugar, "sugar", :sugar_custom},
    {:acidity, "acidity", :acidity_custom},
    {:tannins, "tannins", :tannins_custom},
    {:body, "body", :body_custom},
    {:finish, "finish", :finish_custom}
  ]

  # --- GenHandler Callbacks ---

  @impl true
  def on_boot do
    # Сообщаем, что бот запущен
    Logger.info("Telegex polling Handler initialized")
    # Возвращаем ok и начальное состояние
    %__MODULE__{}
  end

  @impl true
  # def on_update(update, _bot) do
  def on_update(update) do
    cond do
      update.message ->
        handle_message(update.message)

      update.callback_query ->
        handle_callback(update.callback_query)

      true ->
        :ok
    end
  end

  # --- Обработка Сообщений ---

  defp handle_message(msg) do
    chat_id = msg.chat.id

    cond do
      msg.text == "/start" ->
        handle_start(chat_id)

      msg.photo ->
        handle_photo(chat_id, msg.photo)

      msg.text ->
        handle_text(chat_id, msg.text)
    end
  end

  defp handle_start(chat_id) do
    Logger.info("Received /start from #{chat_id}")
    SessionManager.clear_state(chat_id)
    send_menu(chat_id)
  end

  defp handle_photo(chat_id, photos) do
    %{file_id: file_id} = List.last(photos)
    state = SessionManager.get_state(chat_id)
    Logger.info("Photo received from #{chat_id}. Step: #{state.step}")

    if state.step == :editing_photo do
      Task.start(fn ->
        case WineDiaryBot.Media.process_and_upload(file_id) do
          {:ok, url} ->
            Tastings.update_tasting_photo(state.data.editing_tasting_id, url)
            Telegex.send_message(chat_id, "Фото обновлено.")
            show_tasting_detail(chat_id, state.data.editing_tasting_id)
          _ ->
            Telegex.send_message(chat_id, "Ошибка загрузки.")
        end
      end)
    else
      Telegex.send_message(chat_id, "Обрабатываю фото...")
      Task.start(fn ->
        case WineDiaryBot.Media.process_and_upload(file_id) do
          {:ok, url} ->
            SessionManager.set_state(chat_id, %{step: :waiting_name, data: %{image_url: url}})
            Telegex.send_message(chat_id, "Фото сохранено. Введите название вина:")
          {:error, _} ->
            Telegex.send_message(chat_id, "Ошибка загрузки фото.")
        end
      end)
    end
  end

  defp handle_text(chat_id, text) do
    state = SessionManager.get_state(chat_id)
    Logger.debug("Text: '#{text}' from #{chat_id} at #{state.step}")

    case state.step do
      :waiting_name ->
        Logger.info("Saving name: #{text}")
        SessionManager.update_data(chat_id, %{wine_name: text})
        set_step(chat_id, :waiting_vintage)
        Telegex.send_message(chat_id, "Укажите винтаж (год) или /skip:")

      :waiting_vintage ->
        if text == "/skip" do
          ask_for_rating(chat_id)
        else
          case Integer.parse(text) do
            {year, _} ->
              SessionManager.update_data(chat_id, %{vintage: year})
              ask_for_rating(chat_id)
            _ ->
              Telegex.send_message(chat_id, "Неверный год. Введите число или /skip:")
          end
        end

      :waiting_price ->
        if text == "/skip" do
          start_organoleptics(chat_id)
        else
          case Decimal.parse(text) do
            {price, _} ->
              SessionManager.update_data(chat_id, %{price: price})
              start_organoleptics(chat_id)
            :error ->
              Telegex.send_message(chat_id, "Неверная цена. Введите число или /skip:")
          end
        end

      :waiting_org ->
        idx = state.data.current_org_idx
        {step_name, _, field} = Enum.at(@org_steps, idx)

        if text == "/skip" do
          Telegex.send_message(chat_id, "Пропущено.")
        else
          SessionManager.update_data(chat_id, %{field => text})
        end

        ask_org_step(chat_id, idx + 1)

      :editing_rating ->
        case Decimal.parse(text) do
          {r, _} ->
            Tastings.update_tasting_field(state.data.editing_tasting_id, :rating, r)
            Telegex.send_message(chat_id, "Оценка обновлена.")
            show_tasting_detail(chat_id, state.data.editing_tasting_id)
          :error ->
            Telegex.send_message(chat_id, "Неверное число. Введите оценку:")
        end

      _ ->
        Telegex.send_message(chat_id, "Не понял команду. /start")
    end
  end

  # --- Обработка Callback ---

  defp handle_callback(cq) do
    chat_id = cq.message.chat.id
    data = cq.data
    Logger.debug("Callback: #{data} from #{chat_id}")

    case data do
      "action:menu" -> send_menu(chat_id)
      "action:add" -> Telegex.send_message(chat_id, "Отправьте фото этикетки:")
      "action:list" -> show_tastings_list(chat_id)

      "view:" <> id ->
        show_tasting_detail(chat_id, id)

      "edit:photo:" <> id ->
        SessionManager.set_state(chat_id, %{step: :editing_photo, data: %{editing_tasting_id: id}})
        Telegex.send_message(chat_id, "Отправьте новое фото:")

      "edit:rating:" <> id ->
        SessionManager.set_state(chat_id, %{step: :editing_rating, data: %{editing_tasting_id: id}})
        ask_for_rating(chat_id)

      "rate:" <> val ->
        handle_rating_callback(chat_id, val)

      _ -> :ok
    end
    Telegex.answer_callback_query(cq.id, "")
  end

  defp handle_rating_callback(chat_id, val) do
    state = SessionManager.get_state(chat_id)
    Logger.info("Rating callback: #{val}")

    if state.step == :editing_rating do
      Tastings.update_tasting_field(state.data.editing_tasting_id, :rating, Decimal.new(val))
      Telegex.edit_message_text(chat_id, nil, "Оценка обновлена.")
      show_tasting_detail(chat_id, state.data.editing_tasting_id)
    else
      SessionManager.update_data(chat_id, %{rating: Decimal.new(val)})
      Telegex.edit_message_text(chat_id, nil, "Оценка: #{val}.")
      set_step(chat_id, :waiting_price)
      Telegex.send_message(chat_id, "Введите цену (руб) или /skip:")
    end
  end

  # --- Вспомогательные функции UI ---

  defp set_step(chat_id, step) do
    state = SessionManager.get_state(chat_id)
    Logger.debug("[FSM] #{chat_id}: #{state.step} -> #{step}")
    SessionManager.set_state(chat_id, %{state | step: step})
  end

  defp send_menu(chat_id) do
    keyboard = Telegex.Type.InlineKeyboardMarkup.new([
      [Telegex.Type.InlineKeyboardButton.new("➕ Добавить вино", callback_data: "action:add")],
      [Telegex.Type.InlineKeyboardButton.new("📋 Мои дегустации", callback_data: "action:list")]
    ])
    Telegex.send_message(chat_id, "Главное меню:", reply_markup: keyboard)
  end

  defp show_tastings_list(chat_id) do
    user = Accounts.get_or_create_user(chat_id)
    tastings = Tastings.list_user_tastings(user.id)

    text = if tastings == [], do: "Список пуст.", else: "Ваши последние дегустации:"

    buttons = Enum.map(tastings, fn t ->
      name = t.wine.name
      rating = t.rating || "нет"
      Telegex.Type.InlineKeyboardButton.new("#{name} (#{rating})", callback_data: "view:#{t.id}")
    end)

    keyboard = Telegex.Type.InlineKeyboardMarkup.new(buttons ++ [[Telegex.Type.InlineKeyboardButton.new("🏠 Меню", callback_data: "action:menu")]])
    Telegex.send_message(chat_id, text, reply_markup: keyboard)
  end

  defp show_tasting_detail(chat_id, tasting_id) do
    tasting = Tastings.get_tasting!(tasting_id)

    text = """
    🍷 *#{tasting.wine.name}*
    📅 Дата: #{tasting.tasting_date}
    ⭐ Оценка: #{tasting.rating || "нет"}
    """

    keyboard = Telegex.Type.InlineKeyboardMarkup.new([
      [Telegex.Type.InlineKeyboardButton.new("✏️ Изменить оценку", callback_data: "edit:rating:#{tasting_id}")],
      [Telegex.Type.InlineKeyboardButton.new("📸 Изменить фото", callback_data: "edit:photo:#{tasting_id}")],
      [Telegex.Type.InlineKeyboardButton.new("🔙 Назад", callback_data: "action:list")]
    ])

    if tasting.photos && List.first(tasting.photos) do
      Telegex.send_photo(chat_id, List.first(tasting.photos).image_url, caption: text, parse_mode: "Markdown", reply_markup: keyboard)
    else
      Telegex.send_message(chat_id, text, parse_mode: "Markdown", reply_markup: keyboard)
    end
  end

  defp ask_for_rating(chat_id) do
    set_step(chat_id, :waiting_rating)
    buttons = for row <- [0..2, 3..5, 6..8, 9..10] do
      Enum.map(row, fn v -> Telegex.Type.InlineKeyboardButton.new("#{v}", callback_data: "rate:#{v}.0") end)
    end
    keyboard = Telegex.Type.InlineKeyboardMarkup.new(buttons)
    Telegex.send_message(chat_id, "Поставьте оценку:", reply_markup: keyboard)
  end

  defp start_organoleptics(chat_id) do
    Telegex.send_message(chat_id, "🍷 Теперь органолептика.")
    ask_org_step(chat_id, 0)
  end

  defp ask_org_step(chat_id, idx) when idx >= length(@org_steps) do
    save_tasting(chat_id)
  end

  defp ask_org_step(chat_id, idx) do
    {name, _, _} = Enum.at(@org_steps, idx)
    SessionManager.update_data(chat_id, %{current_org_idx: idx})
    set_step(chat_id, :waiting_org)
    Telegex.send_message(chat_id, "#{get_question_text(name)} (или /skip):")
  end

  defp get_question_text(:color), do: "🎨 Цвет?"
  defp get_question_text(:color_intensity), do: "💧 Интенсивность цвета?"
  defp get_question_text(:sugar), do: "🍬 Сахар?"
  defp get_question_text(:acidity), do: "🍋 Кислотность?"
  defp get_question_text(:tannins), do: "🌿 Танины?"
  defp get_question_text(:body), do: "🏋️ Тело?"
  defp get_question_text(:finish), do: "⏳ Послевкусие?"

  defp save_tasting(chat_id) do
    state = SessionManager.get_state(chat_id)
    user = Accounts.get_or_create_user(chat_id)

    Telegex.send_message(chat_id, "💾 Сохраняю дегустацию...")

    case Tastings.create_full_tasting(user.id, state.data) do
      {:ok, _} -> Telegex.send_message(chat_id, "✅ Дегустация успешно сохранена!")
      {:error, changeset} ->
        Logger.error("Save error: #{inspect(changeset.errors)}")
        Telegex.send_message(chat_id, "❌ Ошибка при сохранении.")
    end
    SessionManager.clear_state(chat_id)
  end
end
