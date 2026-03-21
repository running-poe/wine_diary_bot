defmodule WineDiaryBot.References do
  import Ecto.Query
  alias WineDiaryBot.Repo
  require Logger

  def get_values_by_group(group_name) do
    Logger.debug("Fetching reference values for group: #{group_name}")
    from(r in "ref_levels", where: r.group_name == ^group_name, select: r.value)
    |> Repo.all()
  end

  def get_colors do
    Logger.debug("Fetching reference colors")
    from(c in "ref_colors", select: c.name)
    |> Repo.all()
  end
end
