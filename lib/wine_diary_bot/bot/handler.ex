defmodule WineDiaryBot.Bot.Handler do
  use GenServer

  require Logger

  alias WineDiaryBot.Accounts
  alias WineDiaryBot.Tastings
  alias WineDiaryBot.Tastings.TastingPhoto

  # ==========================================
  # API & GenServer Callbacks
  # ==========================================

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("[Handler.init] GenServer started successfully.")
    {:ok, state}
  end

  def handle_update(%{message: message} = update, state) when not is_nil(message) do
    GenServer.cast(__MODULE__, {:message, update})
    {:noreply, state}
  end

  def handle_update(%{callback_query: callback} = update, state) when not is_nil(callback) do
    GenServer.cast(__MODULE__, {:callback, update})
    {:noreply, state}
  end

  def handle_update(_update, state), do: {:noreply, state}

  # ==========================================
  # Internal Logic (Cast Handling)
  # ==========================================

  def handle_cast({:message, update}, state) do
    message = update.message
    chat_id = message.chat.id
    telegram_id = message.from.id

    Logger.debug("[Handler.handle_cast] Received message from telegram_id: #{telegram_id}")

    state = ensure_user(state, telegram_id)
    state = Map.put(state, :chat_id, chat_id)

    if message.photo && length(message.photo) > 0 do
      handle_photo_message(message, state)
    else
      if message.text do
        handle_text_message(message.text, state)
      else
        {:noreply, state}
      end
    end
  end

  def handle_cast({:callback, update}, state) do
    callback = update.callback_query
    chat_id = callback.message.chat.id
    telegram_id = callback.from.id

    Logger.debug("[Handler.handle_cast] Received callback: '#{callback.data}' from telegram_id: #{telegram_id}")

    state = ensure_user(state, telegram_id)
    state = Map.put(state, :chat_id, chat_id)

    handle_callback_query(callback, state)
  end

  # ==========================================
  # User & State Management
  # ==========================================

  defp ensure_user(state, telegram_id) do
    case state[:user] do
      %{telegram_id: ^telegram_id} ->
        Logger.debug("[Handler.ensure_user] User found in state: #{telegram_id}")
        state
      _ ->
        Logger.debug("[Handler.ensure_user] Fetching/Creating user from DB: #{telegram_id}")
        {:ok, user} = Accounts.get_or_create_user(telegram_id)
        Logger.debug("[Handler.ensure_user] User ensured. DB ID: #{user.id}")
        Map.put(state, :user, user)
    end
  end

  defp reset_state(state) do
    Logger.debug("[Handler.reset_state] Clearing step and tasting_data.")
    Map.put(state, :step, nil) |> Map.put(:tasting_data, nil)
  end

  # ==========================================
  # MESSAGE FLOW (Dialog)
  # ==========================================

  defp handle_text_message("/start", state) do
    Logger.debug("[Handler.handle_text_message] Command: /start")
    text = """
    🍷 *Добро пожаловать в Wine Diary!*

    Я помогу вам вести учет ваших винных впечатлений.

    _Команды:_
    /new — Добавить новую дегустацию
    /list — Посмотреть мои дегустации
    """

    send_message(state.chat_id, text, parse_mode: "Markdown")
    {:noreply, reset_state(state)}
  end

  defp handle_text_message("/new", state) do
    Logger.debug("[Handler.handle_text_message] Command: /new")
    text = "🍇 *Начинаем новую дегустацию!*\n\nКак называется вино?"
    send_message(state.chat_id, text, parse_mode: "Markdown")
    {:noreply, Map.put(state, :step, :awaiting_name) |> Map.put(:tasting_data, %{})}
  end

  defp handle_text_message("/list", state) do
    Logger.debug("[Handler.handle_text_message] Command: /list")
    show_tastings_list(state)
    {:noreply, reset_state(state)}
  end

  defp handle_text_message("/cancel", state) do
    Logger.debug("[Handler.handle_text_message] Command: /cancel")
    send_message(state.chat_id, "❌ Действие отменено.")
    {:noreply, reset_state(state)}
  end

  # --- Step 1: Name ---
  defp handle_text_message(text, %{step: :awaiting_name} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_name. Input: '#{text}'")
    data = Map.put(state.tasting_data, :wine_name, text)
    text = "📅 Отлично, *#{text}*.\n\nУкажите год урожая (винтаж) или отправьте '-', если не знаете."
    send_message(state.chat_id, text, parse_mode: "Markdown")
    {:noreply, Map.put(state, :step, :awaiting_vintage) |> Map.put(:tasting_data, data)}
  end

  # --- Step 2: Vintage ---
  defp handle_text_message(text, %{step: :awaiting_vintage} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_vintage. Input: '#{text}'")
    vintage = case Integer.parse(text) do
      {year, _} when year > 1900 and year <= 2100 -> year
      _ -> nil
    end

    data = Map.put(state.tasting_data, :vintage, vintage)

    # Переходим к выбору типа вина
    ask_wine_type(state, data)
  end

  # --- Step 3: Wine Type (Text Input) ---
  defp handle_text_message(text, %{step: :awaiting_wine_type} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_wine_type. Custom Input: '#{text}'")

    data = Map.put(state.tasting_data, :wine_type_custom, text)
    text = "💰 Укажите цену покупки (в рублях) или '-' чтобы пропустить."
    send_message(state.chat_id, text)
    {:noreply, Map.put(state, :step, :awaiting_price) |> Map.put(:tasting_data, data)}
  end

  # --- Step 4: Price ---
  defp handle_text_message(text, %{step: :awaiting_price} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_price. Input: '#{text}'")

    price = case Decimal.parse(text) do
      {:ok, val} -> val
      {val, _remainder} -> val
      :error -> nil
    end

    data = Map.put(state.tasting_data, :price, price)

    text = "📝 Напишите ваши впечатления и заметки (или '-' чтобы пропустить)."
    send_message(state.chat_id, text)
    {:noreply, Map.put(state, :step, :awaiting_notes) |> Map.put(:tasting_data, data)}
  end

  # --- Step 5: Notes ---
  defp handle_text_message(text, %{step: :awaiting_notes} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_notes. Input: '#{text}'")
    notes = if text == "-", do: nil, else: text
    data = Map.put(state.tasting_data, :notes, notes)

    text = "⭐ Поставьте оценку от 1 до 10:"
    send_message(state.chat_id, text)
    {:noreply, Map.put(state, :step, :awaiting_rating) |> Map.put(:tasting_data, data)}
  end

  # --- Step 6: Rating ---
  defp handle_text_message(text, %{step: :awaiting_rating} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_rating. Input: '#{text}'")
    case Integer.parse(text) do
      {rating, _} when rating >= 1 and rating <= 10 ->
        data = Map.put(state.tasting_data, :rating, rating)

        text = "📸 Отправьте фото этикетки или напишите 'skip', чтобы завершить без фото."
        send_message(state.chat_id, text)

        {:noreply, Map.put(state, :step, :awaiting_photo) |> Map.put(:tasting_data, data)}

      _ ->
        Logger.warning("[Handler.handle_text_message] Invalid rating input: '#{text}'")
        send_message(state.chat_id, "⚠️ Пожалуйста, введите число от 1 до 10.")
        {:noreply, state}
    end
  end

  # --- Step 7: Photo Skip ---
  defp handle_text_message("skip", %{step: :awaiting_photo} = state) do
    Logger.debug("[Handler.handle_text_message] Step: awaiting_photo. User skipped photo.")
    finalize_tasting(state)
  end

  defp handle_text_message(_text, %{step: :awaiting_photo} = state) do
    Logger.warning("[Handler.handle_text_message] Step: awaiting_photo. Invalid text input, expected photo or 'skip'.")
    send_message(state.chat_id, "Пожалуйста, отправьте фото или напишите 'skip'.")
    {:noreply, state}
  end

  # --- Fallback ---
  defp handle_text_message(_text, state) do
    Logger.debug("[Handler.handle_text_message] Unknown text input (Fallback).")
    if state[:step] do
      send_message(state.chat_id, "Вы находитесь в процессе ввода. Напишите /cancel чтобы отменить.")
    else
      send_message(state.chat_id, "Я не понял команду. Введите /start.")
    end
    {:noreply, state}
  end

  # ==========================================
  # PHOTO HANDLING
  # ==========================================

  defp handle_photo_message(message, %{step: :awaiting_photo} = state) do
    Logger.debug("[Handler.handle_photo_message] Step: awaiting_photo. Photo received.")
    photo = List.last(message.photo)
    data = Map.put(state.tasting_data, :photo_file_id, photo.file_id)

    finalize_tasting(Map.put(state, :tasting_data, data))
  end

  defp handle_photo_message(_message, state) do
    Logger.warning("[Handler.handle_photo_message] Photo received unexpectedly.")
    send_message(state.chat_id, "Я не ожидал фото сейчас. Сначала выберите действие (/new).")
    {:noreply, state}
  end

  # ==========================================
  # CALLBACK HANDLING
  # ==========================================

  defp handle_callback_query(%{data: "action:list"} = callback, state) do
    Logger.debug("[Handler.handle_callback_query] Action: list")
    Telegex.answer_callback_query(callback.id)
    show_tastings_list(state)
    {:noreply, reset_state(state)}
  end

  defp handle_callback_query(%{data: "action:cancel"} = callback, state) do
    Logger.debug("[Handler.handle_callback_query] Action: cancel")
    Telegex.answer_callback_query(callback.id)
    send_message(state.chat_id, "Отменено.")
    {:noreply, reset_state(state)}
  end

  # --- Обработка выбора типа вина ---
  defp handle_callback_query(%{data: "select_type:skip"} = callback, state) do
    Logger.debug("[Handler.handle_callback_query] Action: select_type:skip")
    Telegex.answer_callback_query(callback.id)

    data = state.tasting_data
    text = "💰 Укажите цену покупки (в рублях) или '-' чтобы пропустить."
    send_message(state.chat_id, text)

    {:noreply, Map.put(state, :step, :awaiting_price) |> Map.put(:tasting_data, data)}
  end

  defp handle_callback_query(%{data: "select_type:" <> id_str} = callback, state) do
    id = String.to_integer(id_str)
    Logger.debug("[Handler.handle_callback_query] Action: select_type. ID: #{id}")

    Telegex.answer_callback_query(callback.id)

    data = Map.put(state.tasting_data, :wine_type_id, id)
    text = "💰 Укажите цену покупки (в рублях) или '-' чтобы пропустить."
    send_message(state.chat_id, text)

    {:noreply, Map.put(state, :step, :awaiting_price) |> Map.put(:tasting_data, data)}
  end

  defp handle_callback_query(_callback, state), do: {:noreply, state}

  # ==========================================
  # LOGIC: WINE TYPE SELECTION
  # ==========================================

  defp ask_wine_type(state, data) do
    types = Tastings.list_wine_types()

    buttons =
      Enum.map(types, fn type ->
        [%{text: type.name, callback_data: "select_type:#{type.id}"}]
      end)
      |> Kernel.++([[%{text: "🚫 Пропустить", callback_data: "select_type:skip"}]])

    keyboard = %{inline_keyboard: buttons}

    text = "🍷 Выберите тип вина из списка или напишите свой вариант:"

    Telegex.send_message(state.chat_id, text, reply_markup: keyboard, parse_mode: "Markdown")

    {:noreply, Map.put(state, :step, :awaiting_wine_type) |> Map.put(:tasting_data, data)}
  end

  # ==========================================
  # LOGIC: LIST & SAVE
  # ==========================================

  defp show_tastings_list(state) do
    Logger.debug("[Handler.show_tastings_list] Fetching tastings for user_id: #{state.user.id}")

    try do
      tastings = Tastings.list_tastings(state.user.id)
      Logger.debug("[Handler.show_tastings_list] Fetched #{length(tastings)} tastings.")

      if Enum.empty?(tastings) do
        send_message(state.chat_id, "📝 Ваш список дегустаций пуст.\nДобавьте новую через /new")
      else
        send_message(state.chat_id, "📚 *Ваши последние дегустации:*", parse_mode: "Markdown")

        Enum.each(tastings, fn tasting ->
          Logger.debug("[Handler.show_tastings_list] Processing tasting ID: #{tasting.id}")

          # Формируем название вина
          base_name = if tasting.wine, do: tasting.wine.name, else: "Неизвестное вино"

          # ИЗМЕНЕНИЕ: Добавляем год к названию
          wine_display = if tasting.vintage do
            "#{base_name}, #{tasting.vintage}"
          else
            base_name
          end

          rating = if tasting.rating, do: "#{tasting.rating}/10", else: "Нет оценки"
          date = Date.to_string(tasting.tasting_date)

          text = """
          🍷 *#{wine_display}*
          📅 _#{date}_
          ⭐ Оценка: #{rating}
          """

          photo_url = case tasting.photos do
            [%TastingPhoto{image_url: url} | _] ->
              Logger.debug("[Handler.show_tastings_list] Photo found: #{url}")
              url
            _ ->
              Logger.debug("[Handler.show_tastings_list] No photo for tasting #{tasting.id}.")
              nil
          end

          if photo_url do
            Logger.debug("[Handler.show_tastings_list] Calling Telegex.send_photo for chat_id: #{state.chat_id}")

            result = Telegex.send_photo(state.chat_id, photo_url, caption: text, parse_mode: "Markdown")

            case result do
              {:ok, _message} ->
                Logger.info("[Handler.show_tastings_list] Photo sent successfully to Telegram.")

              {:error, error} ->
                Logger.error("[Handler.show_tastings_list] Error sending photo: #{inspect(error)}")
                send_message(state.chat_id, "#{text}\n⚠️ _Не удалось загрузить фото_", parse_mode: "Markdown")
            end
          else
            Logger.debug("[Handler.show_tastings_list] Sending text only message.")
            send_message(state.chat_id, text, parse_mode: "Markdown")
          end
        end)
      end
    rescue
      e ->
        Logger.error("[Handler.show_tastings_list] CRITICAL Exception: #{inspect(e)}")
        send_message(state.chat_id, "❌ Произошла ошибка при чтении списка. Попробуйте позже.")
    end
  end

  defp finalize_tasting(state) do
    data = state.tasting_data
    user = state.user

    Logger.info("[Handler.finalize_tasting] Starting save for user_id: #{user.id}")
    Logger.debug("[Handler.finalize_tasting] Tasting data: #{inspect(data)}")

    wine_opts = %{
      wine_type_id: data[:wine_type_id],
      wine_type_custom: data[:wine_type_custom]
    }

    {:ok, wine} = Tastings.get_or_create_wine(data.wine_name, wine_opts)
    Logger.debug("[Handler.finalize_tasting] Wine resolved: #{wine.name} (ID: #{wine.id})")

    attrs = %{
      user_id: user.id,
      wine_id: wine.id,
      tasting_date: Date.utc_today(),
      vintage: data[:vintage],
      rating: data[:rating],
      purchase_price: data[:price],
      general_comment: data[:notes],
      photo_file_id: data[:photo_file_id]
    }

    case Tastings.save_tasting(attrs) do
      {:ok, _} ->
        Logger.info("[Handler.finalize_tasting] Tasting saved successfully.")
        send_message(state.chat_id, "✅ *Дегустация успешно сохранена!*", parse_mode: "Markdown")
      {:error, step, changeset, _} ->
        Logger.error("[Handler.finalize_tasting] Failed at step '#{step}'. Changeset errors: #{inspect(changeset.errors)}")
        send_message(state.chat_id, "❌ Произошла ошибка при сохранении. Попробуйте позже.")
    end

    {:noreply, reset_state(state)}
  end

  # ==========================================
  # HELPERS
  # ==========================================

  defp send_message(chat_id, text, opts \\ []) do
    Telegex.send_message(chat_id, text, opts)
  end
end

# ==========================================
# UPDATES CONSUMER (Polling Worker)
# ==========================================

defmodule WineDiaryBot.Bot.Handler.UpdatesConsumer do
  use GenServer

  require Logger

  alias WineDiaryBot.Bot.Handler

  @poll_interval_ms 1000

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("[UpdatesConsumer.init] Consumer started. Starting polling loop.")
    state = Map.put(state, :offset, 0)
    Process.send_after(self(), :poll, @poll_interval_ms)
    {:ok, state}
  end

  def handle_info(:poll, state) do
    case Telegex.get_updates(offset: state.offset, timeout: 10) do
      {:ok, updates} ->
        new_state = handle_updates(updates, state)
        Process.send_after(self(), :poll, @poll_interval_ms)
        {:noreply, new_state}

      {:error, reason} ->
        Logger.error("[UpdatesConsumer.handle_info] Polling failed: #{inspect(reason)}")
        Process.send_after(self(), :poll, 5000)
        {:noreply, state}
    end
  end

  defp handle_updates(updates, state) do
    Enum.reduce(updates, state, fn update, acc ->
      Handler.handle_update(update, %{})

      new_offset = update.update_id + 1
      Map.put(acc, :offset, max(acc.offset, new_offset))
    end)
  end
end
