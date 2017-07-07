defmodule AdvancedMath do
  @moduledoc """
  This example uses the built-in telemetry module (`Recipe.Debug`),
  which prints log lines with execution time.
  """
  use Recipe

  def steps, do: [:double, :square]

  def double(state) do
    new_number = state.assigns.number * 2

    {:ok, Recipe.assign(state, :number, new_number)}
  end

  def square(state) do
    new_number = state.assigns.number * state.assigns.number

    {:ok, Recipe.assign(state, :number, new_number)}
  end

  def handle_result(state) do
    "=== #{state.assigns.number} ==="
  end

  def handle_error(_step, _error, _state), do: :ok
end

initial_state = Recipe.initial_state
                |> Recipe.assign(:number, 5)

{:ok, correlation_id, result} = Recipe.run(AdvancedMath, initial_state, enable_telemetry: true)

Process.sleep(10) # This is just display logs above the result

IO.puts("correlation id: #{correlation_id}")
IO.puts("result: #{result}")
