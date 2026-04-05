defmodule WineDiaryBot.Bot.Handler do
  use GenServer

  require Logger

  alias WineDiaryBot.Accounts
  alias WineDiaryBot.Tastings
  alias WineDiaryBot.Tastings.TastingPhoto

  # Порядок шагов органолептики
  @org_steps [
    {:color, "Цвет вина", "color"},
    {:color_intensity, "Интенсивность цвета", "intensity"},
    {:aroma_intensity, "Интенсивность аромата", "intensity"},
    {:taste_intensity, "Интенсивность вкуса", "intensity"},
    {:sugar, "Сладость", "sugar"},
    {:acidity, "Кислотность", "acidity"},
    {:tannins, "Танины", "tannins"},
    {:alcohol, "Алкоголь", "alcohol"},
    {:body, "Тело", "body"},
    {:finish, "Послевкусие", "finish"}
  ]

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

    Logger.debug("[Handler.handle_cast] Received callback: #{callback.data} from telegram_id: #{telegram_id}")

    state = ensure_user(state, telegram_id)
    state = Map.put(state, :chat_id, chat_id)

    handle_callback_query(callback, state)
  end

  # ==========================================
  # User & State Management
  # ==========================================

  defp ensure_user(state, telegram_id) do
    case state[:user] do
      %{telegram_id: ^telegram_id} -> state
      _ ->
        Logger.debug("[Handler.ensure_user] Fetching user from DB: #{telegram_id}")
        {:ok, user} = Accounts.get_or_create_user(telegram_id)
        Logger.info("[Handler.ensure_user] User ensured: ID #{user.id}")
        Map.put(state, :user, user)
    end
  end

  defp reset_state(state) do
    Logger.debug("[Handler.reset_state] Resetting state.")
    Map.merge(state, %{step: nil, tasting_data: nil, org_step_index: nil, notes_data: nil, org_message_id: nil})
  end

  # ==========================================
  # MESSAGE FLOW (Dialog)
  # ==========================================

  defp handle_text_message("/start", state) do
    Logger.info("[Handler.handle_text_message] Command: /start")

    text = "🍷 *Добро пожаловать в Wine Diary!*"
    buttons = [
      [%{text: "🆕 Новая дегустация", callback_data: "action:new"}],
      [%{text: "📜 Мои дегустации", callback_data: "action:list"}]
    ]

    send_message(state.chat_id, text, parse_mode: "Markdown", reply_markup: %{inline_keyboard: buttons})
    {:noreply, reset_state(state)}
  end

  defp handle_text_message("/new", state) do
    Logger.info("[Handler.handle_text_message] Command: /new")
    text = "🍇 *Начинаем новую дегустацию!*\n\nКак называется вино?"
    send_message(state.chat_id, text, parse_mode: "Markdown")
    {:noreply, Map.put(state, :step, :awaiting_name) |> Map.put(:tasting_data, %{})}
  end

  defp handle_text_message("/list", state) do
    Logger.info("[Handler.handle_text_message] Command: /list")
    show_tastings_list(state)
    {:noreply, reset_state(state)}
  end

  defp handle_text_message("/cancel", state) do
    Logger.info("[Handler.handle_text_message] Command: /cancel")
    send_message(state.chat_id, "❌ Действие отменено.")
    {:noreply, reset_state(state)}
  end

  # --- Organoleptics Text Input Handler ---
  defp handle_text_message(text, state) do
    index = Map.get(state, :org_step_index)

    if not is_nil(index) do
      Logger.debug("[Handler.handle_text_message] Organoleptics custom input: #{text}")
      {step_key, _title, _group} = Enum.at(@org_steps, index)

      notes = Map.get(state, :notes_data, %{})
      notes = Map.put(notes, String.to_atom("#{step_key}_custom"), text)
      new_state = Map.put(state, :notes_data, notes)

      advance_org_step(new_state)
    else
      handle_text_flow(text, state)
    end
  end

  # --- Basic Flow ---

  defp handle_text_flow(text, %{step: :awaiting_name} = state) do
    Logger.debug("[Handler.handle_text_flow] Step: awaiting_name. Input: #{text}")
    data = Map.put(state.tasting_data, :wine_name, text)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_vintage"}]]
    send_message(state.chat_id, "📅 Год урожая (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_vintage) |> Map.put(:tasting_data, data)}
  end

  defp handle_text_flow(text, %{step: :awaiting_vintage} = state) do
    vintage = case Integer.parse(text) do {y, _} when y > 1900 -> y; _ -> nil end
    data = Map.put(state.tasting_data, :vintage, vintage)
    ask_wine_type(state, data)
  end

  defp handle_text_flow(text, %{step: :awaiting_wine_type} = state) do
    data = Map.put(state.tasting_data, :wine_type_custom, text)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_price"}]]
    send_message(state.chat_id, "💰 Цена (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_price) |> Map.put(:tasting_data, data)}
  end

  defp handle_text_flow(text, %{step: :awaiting_price} = state) do
    price = case Decimal.parse(text) do {:ok, v} -> v; {v, _} -> v; _ -> nil end
    data = Map.put(state.tasting_data, :price, price)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_notes"}]]
    send_message(state.chat_id, "📝 Заметки (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_notes) |> Map.put(:tasting_data, data)}
  end

  defp handle_text_flow(text, %{step: :awaiting_notes} = state) do
    notes = if text == "-", do: nil, else: text
    data = Map.put(state.tasting_data, :notes, notes)

    # ИЗМЕНЕНИЕ: Генерируем кнопки для оценки
    rating_buttons =
      1..10
      |> Enum.chunk_every(2)
      |> Enum.map(fn row ->
        # ИСПРАВЛЕНО: добавлен аргумент row
        Enum.map(row, fn i -> %{text: "#{i}", callback_data: "rate:#{i}"} end)
      end)

    send_message(state.chat_id, "⭐ Поставьте оценку (выберите кнопку или введите число):", reply_markup: %{inline_keyboard: rating_buttons})

    {:noreply, Map.put(state, :step, :awaiting_rating) |> Map.put(:tasting_data, data)}
  end

  defp handle_text_flow(text, %{step: :awaiting_rating} = state) do
    case Integer.parse(text) do
      {rating, _} when rating >= 1 and rating <= 10 ->
        data = Map.put(state.tasting_data, :rating, rating)

        buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_photo"}]]
        send_message(state.chat_id, "📸 Фото этикетки (или пропустить):", reply_markup: %{inline_keyboard: buttons})

        {:noreply, Map.put(state, :step, :awaiting_photo) |> Map.put(:tasting_data, data)}
      _ ->
        Logger.warning("[Handler.handle_text_flow] Invalid rating input: #{text}")
        send_message(state.chat_id, "⚠️ Введите число от 1 до 10.")
        {:noreply, state}
    end
  end

  defp handle_text_flow("skip", %{step: :awaiting_photo} = state) do
    Logger.debug("[Handler.handle_text_flow] Skipping photo.")
    ask_organoleptics(state)
  end

  defp handle_text_flow(_text, %{step: :awaiting_photo} = state) do
    send_message(state.chat_id, "Отправьте фото или 'skip'.")
    {:noreply, state}
  end

  # Fallback
  defp handle_text_flow(_text, state) do
    if state[:step] do
      send_message(state.chat_id, "Вы в процессе ввода. /cancel для отмены.")
    else
      send_message(state.chat_id, "Не понял команду. /start")
    end
    {:noreply, state}
  end

  # ==========================================
  # PHOTO HANDLING
  # ==========================================

  defp handle_photo_message(message, %{step: :awaiting_photo} = state) do
    Logger.debug("[Handler.handle_photo_message] Photo received.")
    photo = List.last(message.photo)
    data = Map.put(state.tasting_data, :photo_file_id, photo.file_id)
    ask_organoleptics(Map.put(state, :tasting_data, data))
  end

  defp handle_photo_message(_message, state) do
    Logger.warning("[Handler.handle_photo_message] Unexpected photo.")
    send_message(state.chat_id, "Я не ожидал фото сейчас.")
    {:noreply, state}
  end

  # ==========================================
  # CALLBACK HANDLING
  # ==========================================

  defp handle_callback_query(%{data: "action:list"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    show_tastings_list(state)
    {:noreply, reset_state(state)}
  end

  defp handle_callback_query(%{data: "action:new"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    text = "🍇 *Начинаем новую дегустацию!*\n\nКак называется вино?"
    Telegex.send_message(state.chat_id, text, parse_mode: "Markdown")
    {:noreply, Map.put(state, :step, :awaiting_name) |> Map.put(:tasting_data, %{})}
  end

  defp handle_callback_query(%{data: "action:cancel"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    send_message(state.chat_id, "Отменено.")
    {:noreply, reset_state(state)}
  end

  # Wine Type Callbacks
  defp handle_callback_query(%{data: "select_type:skip"} = callback, state) do
    Telegex.answer_callback_query(callback.id)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_price"}]]
    send_message(state.chat_id, "💰 Цена (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_price) |> Map.put(:tasting_data, state.tasting_data)}
  end

  defp handle_callback_query(%{data: "select_type:" <> id_str} = callback, state) do
    id = String.to_integer(id_str)
    Telegex.answer_callback_query(callback.id)
    data = Map.put(state.tasting_data, :wine_type_id, id)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_price"}]]
    send_message(state.chat_id, "💰 Цена (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_price) |> Map.put(:tasting_data, data)}
  end

  # Skip callbacks for inputs
  defp handle_callback_query(%{data: "skip_vintage"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    Logger.debug("[Handler] Skipping vintage via button.")
    data = Map.put(state.tasting_data, :vintage, nil)
    ask_wine_type(state, data)
  end

  defp handle_callback_query(%{data: "skip_price"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    Logger.debug("[Handler] Skipping price via button.")
    data = Map.put(state.tasting_data, :price, nil)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_notes"}]]
    send_message(state.chat_id, "📝 Заметки (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_notes) |> Map.put(:tasting_data, data)}
  end

  defp handle_callback_query(%{data: "skip_notes"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    Logger.debug("[Handler] Skipping notes via button.")
    data = Map.put(state.tasting_data, :notes, nil)

    # ИЗМЕНЕНИЕ: Генерируем кнопки для оценки
    rating_buttons =
      1..10
      |> Enum.chunk_every(2)
      |> Enum.map(fn row ->
        # ИСПРАВЛЕНО: добавлен аргумент row
        Enum.map(row, fn i -> %{text: "#{i}", callback_data: "rate:#{i}"} end)
      end)

    send_message(state.chat_id, "⭐ Поставьте оценку (выберите кнопку или введите число):", reply_markup: %{inline_keyboard: rating_buttons})

    {:noreply, Map.put(state, :step, :awaiting_rating) |> Map.put(:tasting_data, data)}
  end

  # ИЗМЕНЕНИЕ: Обработка нажатия кнопки оценки
  defp handle_callback_query(%{data: "rate:" <> val_str} = callback, state) do
    {val, _} = Integer.parse(val_str)

    if val >= 1 and val <= 10 do
      Telegex.answer_callback_query(callback.id)
      Logger.info("[Handler] Rating selected via button: #{val}")

      data = Map.put(state.tasting_data, :rating, val)

      # Переход к фото с кнопкой пропуска
      buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_photo"}]]
      send_message(state.chat_id, "📸 Фото этикетки (или пропустить):", reply_markup: %{inline_keyboard: buttons})

      {:noreply, Map.put(state, :step, :awaiting_photo) |> Map.put(:tasting_data, data)}
    else
      Telegex.answer_callback_query(callback.id, "Неверная оценка.")
      {:noreply, state}
    end
  end

  defp handle_callback_query(%{data: "skip_photo"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    Logger.debug("[Handler] Skipping photo via button.")
    ask_organoleptics(state)
  end

  # Organoleptics: Start
  defp handle_callback_query(%{data: "org:start"} = callback, state) do
    if is_nil(state[:tasting_data]) do
      Logger.warning("[Handler] org:start called with empty state (session expired).")
      Telegex.answer_callback_query(callback.id, "Сессия устарела. Введите /new")
      Telegex.delete_message(state.chat_id, callback.message.message_id)
      {:noreply, reset_state(state)}
    else
      Telegex.answer_callback_query(callback.id)
      Telegex.delete_message(state.chat_id, callback.message.message_id)

      Logger.info("[Handler] Starting organoleptics wizard.")
      new_state = Map.merge(state, %{org_step_index: 0, notes_data: %{}})
      msg_id = show_org_step(new_state)
      {:noreply, Map.put(new_state, :org_message_id, msg_id)}
    end
  end

  defp handle_callback_query(%{data: "org:skip"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    Logger.info("[Handler] Skipping organoleptics.")
    finalize_tasting(state)
  end

  # Organoleptics: Navigation
  defp handle_callback_query(%{data: "org:back"} = callback, state) do
    Telegex.answer_callback_query(callback.id)

    current_index = Map.get(state, :org_step_index, 0)
    new_index = max(0, current_index - 1)

    msg_id = Map.get(state, :org_message_id)
    if msg_id, do: Telegex.delete_message(state.chat_id, msg_id)

    new_state = Map.put(state, :org_step_index, new_index)
    new_msg_id = show_org_step(new_state)
    {:noreply, Map.put(new_state, :org_message_id, new_msg_id)}
  end

  # Organoleptics: Value Selection
  defp handle_callback_query(%{data: "org:sel:" <> rest} = callback, state) do
    [field_name, id_str] = String.split(rest, ":", parts: 2)
    id = String.to_integer(id_str)

    Telegex.answer_callback_query(callback.id)

    notes = Map.get(state, :notes_data, %{})
    notes = Map.put(notes, String.to_atom("#{field_name}_id"), id)
    new_state = Map.put(state, :notes_data, notes)

    advance_org_step(new_state)
  end

  defp handle_callback_query(%{data: "org:save"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    finalize_tasting(state)
  end

  defp handle_callback_query(_callback, state), do: {:noreply, state}

  # ==========================================
  # LOGIC: HELPERS & SCREENS
  # ==========================================

  defp ask_wine_type(state, data) do
    types = Tastings.list_wine_types()

    buttons =
      Enum.map(types, fn type ->
        [%{text: type.name, callback_data: "select_type:#{type.id}"}]
      end)
      |> Kernel.++([[%{text: "🚫 Пропустить", callback_data: "select_type:skip"}]])

    Telegex.send_message(state.chat_id, "🍷 Выберите тип вина:", reply_markup: %{inline_keyboard: buttons})
    {:noreply, Map.put(state, :step, :awaiting_wine_type) |> Map.put(:tasting_data, data)}
  end

  defp ask_organoleptics(state) do
    text = "🧪 Желаете заполнить органолептические свойства?"
    buttons = [
      [%{text: "✅ Да, заполнить", callback_data: "org:start"}],
      [%{text: "❌ Нет, пропустить", callback_data: "org:skip"}]
    ]
    Telegex.send_message(state.chat_id, text, reply_markup: %{inline_keyboard: buttons})
    {:noreply, Map.put(state, :step, :awaiting_org_decision)}
  end

  # Функция перехода к следующему шагу
  defp advance_org_step(state) do
    current_index = Map.get(state, :org_step_index, 0)
    next_index = current_index + 1

    if next_index >= length(@org_steps) do
      finalize_tasting(state)
    else
      msg_id = Map.get(state, :org_message_id)
      if msg_id, do: Telegex.delete_message(state.chat_id, msg_id)

      new_state = Map.put(state, :org_step_index, next_index)
      new_msg_id = show_org_step(new_state)

      {:noreply, Map.put(new_state, :org_message_id, new_msg_id)}
    end
  end

  # Рендер текущего шага органолептики
  defp show_org_step(state) do
    index = Map.get(state, :org_step_index, 0)

    if index >= length(@org_steps) do
      nil
    else
      {step_key, title, group} = Enum.at(@org_steps, index)

      items = if step_key == :color do
        Tastings.list_colors()
        |> Enum.map(fn item -> %{text: item.name, callback_data: "org:sel:color:#{item.id}"} end)
      else
        Tastings.list_levels_by_group(group)
        |> Enum.map(fn item -> %{text: item.value, callback_data: "org:sel:#{step_key}:#{item.id}"} end)
      end

      nav_buttons = []
      nav_buttons = if index > 0, do: nav_buttons ++ [%{text: "⬅️ Назад", callback_data: "org:back"}], else: nav_buttons
      nav_buttons = nav_buttons ++ [%{text: "🏁 Завершить", callback_data: "org:save"}]

      value_rows = Enum.chunk_every(items, 2)
      keyboard = value_rows ++ [nav_buttons]

      case Telegex.send_message(state.chat_id, "*#{title}*\n(Можно выбрать кнопку или написать свой вариант)", parse_mode: "Markdown", reply_markup: %{inline_keyboard: keyboard}) do
        {:ok, message} -> message.message_id
        _ -> nil
      end
    end
  end

  defp finalize_tasting(state) do
    data = Map.get(state, :tasting_data)
    user = state[:user]

    if is_nil(data) or is_nil(user) do
      Logger.error("[Handler.finalize_tasting] State lost or user missing.")
      send_message(state.chat_id, "❌ Сессия устарела. Пожалуйста, начните заново /new")
      {:noreply, reset_state(state)}
    else
      Logger.info("[Handler.finalize_tasting] Saving tasting for User #{user.id}")

      wine_opts = %{
        wine_type_id: data[:wine_type_id],
        wine_type_custom: data[:wine_type_custom]
      }

      {:ok, wine} = Tastings.get_or_create_wine(data.wine_name, wine_opts)

      attrs = %{
        user_id: user.id,
        wine_id: wine.id,
        tasting_date: Date.utc_today(),
        vintage: data[:vintage],
        rating: data[:rating],
        purchase_price: data[:price],
        general_comment: data[:notes],
        photo_file_id: data[:photo_file_id],
        notes: Map.get(state, :notes_data, %{})
      }

      case Tastings.save_tasting(attrs) do
        {:ok, _} ->
          Logger.info("[Handler.finalize_tasting] Success.")
          send_message(state.chat_id, "✅ *Дегустация успешно сохранена!*", parse_mode: "Markdown")
        {:error, step, changeset, _} ->
          Logger.error("[Handler.finalize_tasting] Failed at #{step}. Errors: #{inspect(changeset.errors)}")
          send_message(state.chat_id, "❌ Ошибка при сохранении.")
      end

      {:noreply, reset_state(state)}
    end
  end

  defp show_tastings_list(state) do
    user = state[:user]
    if is_nil(user) do
      Logger.error("[Handler.show_tastings_list] User missing in state.")
      send_message(state.chat_id, "Ошибка авторизации. /start")
    else
      tastings = Tastings.list_tastings(user.id)

      if Enum.empty?(tastings) do
        send_message(state.chat_id, "📝 Список пуст.")
      else
        send_message(state.chat_id, "📚 *Ваши дегустации:*", parse_mode: "Markdown")

        Enum.each(tastings, fn tasting ->
          wine_name = if tasting.wine, do: tasting.wine.name, else: "Неизвестно"
          wine_display = if tasting.vintage, do: "#{wine_name}, #{tasting.vintage}", else: wine_name
          rating = if tasting.rating, do: "#{tasting.rating}/10", else: "Нет оценки"
          date = Date.to_string(tasting.tasting_date)

          text = "🍷 *#{wine_display}*\n📅 _#{date}_\n⭐ Оценка: #{rating}"

          photo_url = case tasting.photos do
            [%TastingPhoto{image_url: url} | _] -> url
            _ -> nil
          end

          if photo_url do
            case Telegex.send_photo(state.chat_id, photo_url, caption: text, parse_mode: "Markdown") do
              {:ok, _} -> :ok
              {:error, _} -> send_message(state.chat_id, "#{text}\n⚠️ _Нет фото_", parse_mode: "Markdown")
            end
          else
            send_message(state.chat_id, text, parse_mode: "Markdown")
          end
        end)
      end
    end
  end

  defp send_message(chat_id, text, opts \\ []) do
    Telegex.send_message(chat_id, text, opts)
  end
end

# ==========================================
# UPDATES CONSUMER
# ==========================================

defmodule WineDiaryBot.Bot.Handler.UpdatesConsumer do
  use GenServer
  require Logger
  alias WineDiaryBot.Bot.Handler

  def start_link(_), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  def init(state) do
    Logger.info("[UpdatesConsumer.init] Consumer started.")
    Process.send_after(self(), :poll, 1000)
    {:ok, Map.put(state, :offset, 0)}
  end

  def handle_info(:poll, state) do
    case Telegex.get_updates(offset: state.offset, timeout: 10) do
      {:ok, updates} ->
        Enum.each(updates, fn u -> Handler.handle_update(u, %{}) end)
        new_offset = if List.last(updates), do: List.last(updates).update_id + 1, else: state.offset
        Process.send_after(self(), :poll, 1000)
        {:noreply, Map.put(state, :offset, new_offset)}
      {:error, r} ->
        Logger.error("[UpdatesConsumer] Poll error: #{inspect(r)}")
        Process.send_after(self(), :poll, 5000)
        {:noreply, state}
    end
  end
end
