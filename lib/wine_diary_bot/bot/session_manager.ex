defmodule WineDiaryBot.Bot.SessionManager do
  use GenServer

  @table :bot_sessions

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table, [:set, :public, :named_table])
    {:ok, %{}}
  end

  def get_state(chat_id) do
    case :ets.lookup(@table, chat_id) do
      [{^chat_id, state}] -> state
      [] -> %{step: :idle, data: %{}}
    end
  end

  def set_state(chat_id, state), do: :ets.insert(@table, {chat_id, state})
  def clear_state(chat_id), do: :ets.delete(@table, chat_id)

  def update_data(chat_id, new_data) do
    state = get_state(chat_id)
    set_state(chat_id, %{state | data: Map.merge(state.data, new_data)})
  end
end
