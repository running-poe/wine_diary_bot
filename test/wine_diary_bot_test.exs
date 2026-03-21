defmodule WineDiaryBotTest do
  use ExUnit.Case
  doctest WineDiaryBot

  test "greets the world" do
    assert WineDiaryBot.hello() == :world
  end
end
