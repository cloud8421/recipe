defmodule RecipeTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  doctest Recipe

  defmodule Successful do
    use Recipe

    def steps, do: [:square, :double]

    def handle_result(state) do
      {:ok, state.assigns.number}
    end

    def handle_error(_step, _error, _state), do: :cannot_fail

    def square(state) do
      number = state.assigns.number
      {:ok, Recipe.assign(state, :number, number * number)}
    end

    def double(state) do
      number = state.assigns.number
      {:ok, Recipe.assign(state, :number, number * 2)}
    end
  end

  describe "successful recipe" do
    test "returns the final result" do
      state = Recipe.empty_state
              |> Recipe.assign(:number, 4)

      assert {:ok, 32} == Recipe.run(Successful, state)
    end

  end

  describe "debug options" do
    test "id supports a correlation id" do
      expected_log = """
      recipe=RecipeTest.Successful step=square assigns=%{number: 4}
      recipe=RecipeTest.Successful step=double assigns=%{number: 16}
      """

      assert capture_log(fn ->
        state = Recipe.empty_state
                |> Recipe.assign(:number, 4)

        Recipe.run(Successful, state, log_steps: true)
      end) == expected_log
    end
  end
end
