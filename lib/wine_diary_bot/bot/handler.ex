defmodule WineDiaryBot.Bot.Handler do
  use GenServer

  require Logger

  alias WineDiaryBot.Accounts
  alias WineDiaryBot.Tastings
  alias WineDiaryBot.Tastings.TastingPhoto

  # ==========================================
  # STEPS DEFINITION
  # ==========================================

  # Новые шаги для ввода данных о вине (Producer -> Country -> Region -> Name)
  @wine_info_steps [
    {:producer, "Производитель/бренд"},
    {:country, "Страна"},
    {:region, "Регион/Аппеласьон"},
    {:wine_name, "Название вина"}
    # wine_name - это обязательное поле, оно было первым, теперь стало четвертым
  ]

  # Шаги органолептики
  @org_steps [
    {:color, "Цвет вина", "color"},
    {:color_intensity, "Интенсивность цвета", "intensity"},
    {:aroma_intensity, "Интенсивность аромата", "intensity"},
    {:taste_intensity, "Интенсивность вкуса", "intensity"},
    {:sugar, "Сладость", "sugar"},
    {:acidity, "Кислотность", "acidity"},
    {:tannins, "Танины", "tannins"},
    {:abv, "Крепость (%)", "abv"},
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
    Map.merge(state, %{
      step: nil,
      tasting_data: nil,
      org_step_index: nil,
      notes_data: nil,
      org_message_id: nil,
      wine_wizard_index: nil, # Сброс индекса мастера вина
      wine_wizard_msg_id: nil
    })
  end

  # ==========================================
  # MESSAGE FLOW (Router)
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
    # Запускаем мастер ввода вина
    start_wine_wizard(state)
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

  # --- Dispatcher ---

  defp handle_text_message(text, state) do
    cond do
      # Обработка ввода в мастере органолептики
      not is_nil(Map.get(state, :org_step_index)) ->
        handle_org_text_input(text, state)

      # Обработка ввода в мастере данных о вине
      not is_nil(Map.get(state, :wine_wizard_index)) ->
        handle_wine_wizard_text_input(text, state)

      # Обработка стандартного потока
      true ->
        handle_text_flow(text, state)
    end
  end

  # ==========================================
  # WINE INFO WIZARD (New Logic)
  # ==========================================

  # Инициализация мастера
  defp start_wine_wizard(state) do
    text = "🍇 *Начинаем новую дегустацию!*"
    send_message(state.chat_id, text, parse_mode: "Markdown")

    new_state = Map.merge(state, %{
      step: :wine_wizard,
      tasting_data: %{},
      wine_wizard_index: 0
    })

    msg_id = show_wine_wizard_step(new_state)
    {:noreply, Map.put(new_state, :wine_wizard_msg_id, msg_id)}
  end

  # Отображение текущего шага мастера вина
  defp show_wine_wizard_step(state) do
    index = Map.get(state, :wine_wizard_index, 0)
    {step_key, title} = Enum.at(@wine_info_steps, index)

    nav_buttons = []
    nav_buttons = if index > 0, do: nav_buttons ++ [%{text: "⬅️ Назад", callback_data: "wine_wizard:back"}], else: nav_buttons

    # Для названия вина (последний шаг) делаем кнопку "Завершить", для остальных "Пропустить"
    is_last_step = (index == length(@wine_info_steps) - 1)

    nav_buttons = if is_last_step do
      nav_buttons ++ [%{text: "🏁 Далее", callback_data: "wine_wizard:next"}]
    else
      nav_buttons ++ [%{text: "Пропустить ⏭️", callback_data: "wine_wizard:next"}]
    end

    keyboard = [nav_buttons]

    hint = if step_key == :wine_name, do: "\n(Обязательное поле)", else: ""

    case Telegex.send_message(state.chat_id, "*#{title}*#{hint}", parse_mode: "Markdown", reply_markup: %{inline_keyboard: keyboard}) do
      {:ok, message} -> message.message_id
      _ -> nil
    end
  end

  # Обработка текстового ввода в мастере вина
  defp handle_wine_wizard_text_input(text, state) do
    index = Map.get(state, :wine_wizard_index, 0)
    {step_key, _title} = Enum.at(@wine_info_steps, index)

    data = Map.get(state, :tasting_data, %{})

    # Маппинг ключа шага на ключ в tasting_data
    # note: :wine_name maps to :wine_name, others to :producer_custom etc.
    data_key = case step_key do
      :wine_name -> :wine_name
      :producer -> :producer_custom
      :country -> :country_custom
      :region -> :region_custom
    end

    new_data = Map.put(data, data_key, text)
    new_state = Map.put(state, :tasting_data, new_data)

    advance_wine_wizard_step(new_state)
  end

  # Переход к следующему шагу мастера вина
  defp advance_wine_wizard_step(state) do
    index = Map.get(state, :wine_wizard_index, 0)
    next_index = index + 1

    # Удаляем старое сообщение
    msg_id = Map.get(state, :wine_wizard_msg_id)
    if msg_id, do: Telegex.delete_message(state.chat_id, msg_id)

    if next_index >= length(@wine_info_steps) do
      # Мастер вина завершен. Переходим к вводу года (старый поток)
      Logger.info("[Handler] Wine wizard finished. Transitioning to vintage.")

      data = Map.get(state, :tasting_data, %{})

      # Проверка обязательного поля Name
      if is_nil(data[:wine_name]) or String.trim(data[:wine_name]) == "" do
        # Если название пустое, просим ввести снова (не пускаем дальше)
        send_message(state.chat_id, "⚠️ Название вина обязательно! Введите название:")
        new_state = Map.put(state, :wine_wizard_index, index) # Возвращаем на тот же шаг
        msg_id = show_wine_wizard_step(new_state)
        {:noreply, Map.put(new_state, :wine_wizard_msg_id, msg_id)}
      else
        # Все хорошо, идем дальше
        buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_vintage"}]]
        send_message(state.chat_id, "📅 Год урожая (или пропустить):", reply_markup: %{inline_keyboard: buttons})

        {:noreply, Map.put(state, :step, :awaiting_vintage) |> Map.put(:wine_wizard_index, nil)}
      end
    else
      new_state = Map.put(state, :wine_wizard_index, next_index)
      new_msg_id = show_wine_wizard_step(new_state)
      {:noreply, Map.put(new_state, :wine_wizard_msg_id, new_msg_id)}
    end
  end

  # ==========================================
  # ORGANOLEPTICS WIZARD (Existing Logic)
  # ==========================================

  defp handle_org_text_input(text, state) do
    Logger.debug("[Handler.handle_text_message] Organoleptics custom input: #{text}")
    index = Map.get(state, :org_step_index, 0)
    {step_key, _title, _group} = Enum.at(@org_steps, index)

    notes = Map.get(state, :notes_data, %{})

    notes = if step_key == :abv do
      parse_abv(text)
      |> case do
        {:ok, val} ->
          Logger.info("[Handler] ABV parsed from text: #{val}")
          Map.put(notes, :abv, val)
        :error ->
          Logger.warning("[Handler] Failed to parse ABV: #{text}")
          notes
      end
    else
      Map.put(notes, String.to_atom("#{step_key}_custom"), text)
    end

    new_state = Map.put(state, :notes_data, notes)

    if step_key == :abv and not Map.has_key?(notes, :abv) do
         {:noreply, state}
    else
      advance_org_step(new_state)
    end
  end

  defp parse_abv(text) do
    clean_text = text
    |> String.trim()
    |> String.replace(",", ".")

    case Decimal.parse(clean_text) do
      {:ok, val} -> {:ok, val}
      {val, _} -> {:ok, val}
      :error -> :error
    end
  end

  # ==========================================
  # BASIC FLOW (Existing Logic)
  # ==========================================

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

    rating_buttons =
      1..10
      |> Enum.chunk_every(2)
      |> Enum.map(fn row ->
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
    send_message(state.chat_id, "Отправьте фото или нажмите 'Пропустить'.")
    {:noreply, state}
  end

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
    start_wine_wizard(state)
  end

  defp handle_callback_query(%{data: "action:cancel"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    send_message(state.chat_id, "Отменено.")
    {:noreply, reset_state(state)}
  end

  # --- Wine Wizard Navigation Callbacks ---

  defp handle_callback_query(%{data: "wine_wizard:back"} = callback, state) do
    Telegex.answer_callback_query(callback.id)

    index = Map.get(state, :wine_wizard_index, 0)
    new_index = max(0, index - 1)

    msg_id = Map.get(state, :wine_wizard_msg_id)
    if msg_id, do: Telegex.delete_message(state.chat_id, msg_id)

    new_state = Map.put(state, :wine_wizard_index, new_index)
    new_msg_id = show_wine_wizard_step(new_state)
    {:noreply, Map.put(new_state, :wine_wizard_msg_id, new_msg_id)}
  end

  defp handle_callback_query(%{data: "wine_wizard:next"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    # Просто переходим дальше, данные уже введены или пропущены
    advance_wine_wizard_step(state)
  end

  # --- Standard Flow Callbacks ---

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
    data = Map.put(state.tasting_data, :vintage, nil)
    ask_wine_type(state, data)
  end

  defp handle_callback_query(%{data: "skip_price"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    data = Map.put(state.tasting_data, :price, nil)

    buttons = [[%{text: "Пропустить ⏭️", callback_data: "skip_notes"}]]
    send_message(state.chat_id, "📝 Заметки (или пропустить):", reply_markup: %{inline_keyboard: buttons})

    {:noreply, Map.put(state, :step, :awaiting_notes) |> Map.put(:tasting_data, data)}
  end

  defp handle_callback_query(%{data: "skip_notes"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    data = Map.put(state.tasting_data, :notes, nil)

    rating_buttons =
      1..10
      |> Enum.chunk_every(2)
      |> Enum.map(fn row ->
        Enum.map(row, fn i -> %{text: "#{i}", callback_data: "rate:#{i}"} end)
      end)

    send_message(state.chat_id, "⭐ Поставьте оценку:", reply_markup: %{inline_keyboard: rating_buttons})

    {:noreply, Map.put(state, :step, :awaiting_rating) |> Map.put(:tasting_data, data)}
  end

  defp handle_callback_query(%{data: "rate:" <> val_str} = callback, state) do
    {val, _} = Integer.parse(val_str)

    if val >= 1 and val <= 10 do
      Telegex.answer_callback_query(callback.id)
      data = Map.put(state.tasting_data, :rating, val)

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
    ask_organoleptics(state)
  end

  # --- Organoleptics Callbacks ---

  defp handle_callback_query(%{data: "org:start"} = callback, state) do
    if is_nil(state[:tasting_data]) do
      Telegex.answer_callback_query(callback.id, "Сессия устарела. Введите /new")
      Telegex.delete_message(state.chat_id, callback.message.message_id)
      {:noreply, reset_state(state)}
    else
      Telegex.answer_callback_query(callback.id)
      Telegex.delete_message(state.chat_id, callback.message.message_id)

      new_state = Map.merge(state, %{org_step_index: 0, notes_data: %{}})
      msg_id = show_org_step(new_state)
      {:noreply, Map.put(new_state, :org_message_id, msg_id)}
    end
  end

  defp handle_callback_query(%{data: "org:skip"} = callback, state) do
    Telegex.answer_callback_query(callback.id)
    finalize_tasting(state)
  end

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

  defp handle_callback_query(%{data: "org:sel:" <> rest} = callback, state) do
    [field_name, id_str] = String.split(rest, ":", parts: 2)

    Telegex.answer_callback_query(callback.id)

    notes = Map.get(state, :notes_data, %{})

    notes = if field_name == "abv" do
      case Decimal.parse(id_str) do
        {:ok, val} -> Map.put(notes, :abv, val)
        {val, _} -> Map.put(notes, :abv, val)
        :error -> notes
      end
    else
      id = String.to_integer(id_str)
      Map.put(notes, String.to_atom("#{field_name}_id"), id)
    end

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

  defp show_org_step(state) do
    index = Map.get(state, :org_step_index, 0)

    if index >= length(@org_steps) do
      nil
    else
      {step_key, title, group} = Enum.at(@org_steps, index)

      items = cond do
        step_key == :abv ->
          9..19
          |> Enum.to_list()
          |> Enum.chunk_every(4)
          |> List.flatten()
          |> Enum.map(fn i -> %{text: "#{i}", callback_data: "org:sel:abv:#{i}"} end)
          |> Enum.chunk_every(4)

        step_key == :color ->
          Tastings.list_colors()
          |> Enum.map(fn item -> %{text: item.name, callback_data: "org:sel:color:#{item.id}"} end)

        true ->
          Tastings.list_levels_by_group(group)
          |> Enum.map(fn item -> %{text: item.value, callback_data: "org:sel:#{step_key}:#{item.id}"} end)
      end

      nav_buttons = []
      nav_buttons = if index > 0, do: nav_buttons ++ [%{text: "⬅️ Назад", callback_data: "org:back"}], else: nav_buttons
      nav_buttons = nav_buttons ++ [%{text: "🏁 Завершить", callback_data: "org:save"}]

      value_rows = if step_key == :abv do
        items
      else
        Enum.chunk_every(items, 2)
      end

      keyboard = value_rows ++ [nav_buttons]

      hint = if step_key == :abv, do: "\n(Выберите кнопку или введите значение, например 12,5)", else: "\n(Можно выбрать кнопку или написать свой вариант)"

      case Telegex.send_message(state.chat_id, "*#{title}*#{hint}", parse_mode: "Markdown", reply_markup: %{inline_keyboard: keyboard}) do
        {:ok, message} -> message.message_id
        _ -> nil
      end
    end
  end

  defp finalize_tasting(state) do
    data = Map.get(state, :tasting_data)
    user = state[:user]

    if is_nil(data) or is_nil(user) or is_nil(data[:wine_name]) do
      send_message(state.chat_id, "❌ Сессия устарела или не все поля заполнены. Начните заново /new")
      {:noreply, reset_state(state)}
    else
      Logger.info("[Handler.finalize_tasting] Saving tasting for User #{user.id}")

      wine_opts = %{
        wine_type_id: data[:wine_type_id],
        wine_type_custom: data[:wine_type_custom],
        producer_custom: data[:producer_custom],
        country_custom: data[:country_custom],
        region_custom: data[:region_custom]
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
      send_message(state.chat_id, "Ошибка авторизации. /start")
    else
      tastings = Tastings.list_tastings(user.id)

      if Enum.empty?(tastings) do
        send_message(state.chat_id, "📝 Список пуст.")
      else
        send_message(state.chat_id, "📚 *Ваши дегустации:*", parse_mode: "Markdown")

        Enum.each(tastings, fn tasting ->
          wine_name = if tasting.wine, do: tasting.wine.name, else: "Неизвестно"

          # Формируем название с учетом новых полей
          wine_display = wine_name

          # Добавляем год, если есть
          wine_display = if tasting.vintage, do: "#{wine_display}, #{tasting.vintage}", else: wine_display

          rating = if tasting.rating, do: "#{tasting.rating}/10", else: "Нет оценки"
          date = Date.to_string(tasting.tasting_date)

          text = "🍷 *#{wine_display}*\n📅 _#{date}_\n⭐ Оценка: #{rating}"

          text = if tasting.note && tasting.note.abv do
            "#{text}\n🍾 Крепость: #{tasting.note.abv}%"
          else
            text
          end

          text = if tasting.general_comment && String.trim(tasting.general_comment) != "" do
            comment_preview = String.slice(tasting.general_comment, 0, 100)
            suffix = if String.length(tasting.general_comment) > 100, do: "...", else: ""
            "#{text}\n📝 Заметки: #{comment_preview}#{suffix}"
          else
            text
          end

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
