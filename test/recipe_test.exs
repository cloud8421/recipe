defmodule RecipeTest do
  use ExUnit.Case
  doctest Recipe

  defmodule Successful do
    use Recipe

    def run(number) do
      state = Recipe.empty_state
              |> Recipe.assign(:number, number)

      Recipe.run(__MODULE__, state)
    end

    def steps, do: [:square, :double]

    def handle_result(state) do
      {:ok, state.assigns.number}
    end

    def handle_error(_step, _error, _state), do: :cannot_fail

    def square(state) do
      number = state.assigns.number
      {:ok, Recipe.assign(state, :number, number*number)}
    end

    def double(state) do
      number = state.assigns.number
      {:ok, Recipe.assign(state, :number, number * 2)}
    end
  end

  describe "successful recipe" do
    test "returns the final result" do
      assert {:ok, 32} == Successful.run(4)
    end
  end
end
