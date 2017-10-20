defmodule Recipe.Debug do
  @moduledoc """
  Built-in telemetry module which uses `Logger` to report events related to
  a recipe run.

  Implements the `Recipe.Telemetry` behaviour.
  """
  use Recipe.Telemetry

  require Logger

  @doc false
  def on_start(state) do
    Logger.debug(fn ->
      %{recipe_module: recipe, correlation_id: id, assigns: assigns} = state
      "recipe=#{inspect(recipe)} evt=start correlation_id=#{id} assigns=#{inspect(assigns)}"
    end)
  end

  @doc false
  def on_finish(state) do
    Logger.debug(fn ->
      %{recipe_module: recipe, correlation_id: id, assigns: assigns} = state
      "recipe=#{inspect(recipe)} evt=end correlation_id=#{id} assigns=#{inspect(assigns)}"
    end)
  end

  @doc false
  def on_success(step, state, elapsed) do
    Logger.debug(fn ->
      %{recipe_module: recipe, correlation_id: id, assigns: assigns} = state

      "recipe=#{inspect(recipe)} evt=step correlation_id=#{id} step=#{step} assigns=#{
        inspect(assigns)
      } duration=#{elapsed}"
    end)
  end

  @doc false
  def on_error(step, error, state, elapsed) do
    Logger.error(fn ->
      %{recipe_module: recipe, correlation_id: id, assigns: assigns} = state

      "recipe=#{inspect(recipe)} evt=error correlation_id=#{id} step=#{step} error=#{
        inspect(error)
      } assigns=#{inspect(assigns)} duration=#{elapsed}"
    end)
  end
end
