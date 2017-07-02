defmodule RecipeTest do
  use ExUnit.Case
  import ExUnit.CaptureLog

  doctest Recipe

  defmodule Successful do
    use Recipe

    def steps, do: [:square, :double]

    def handle_result(state) do
      state.assigns.number
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

  describe "recipe run" do
    test "returns the final result" do
      state = Recipe.empty_state
              |> Recipe.assign(:number, 4)

      assert {:ok, _, 32} = Recipe.run(Successful, state)
    end

    test "it reuses a correlation id if passed" do
      correlation_id = Recipe.UUID.generate()
      state = Recipe.empty_state
              |> Recipe.assign(:number, 4)

      assert {:ok, correlation_id, 32} ==
        Recipe.run(Successful, state, correlation_id: correlation_id)
    end
  end

  describe "debug options" do
    test "supports logging to debug" do
      correlation_id = Recipe.UUID.generate()
      expected_log = """
      [debug] recipe=RecipeTest.Successful correlation_id=#{correlation_id} step=square assigns=%{number: 4}
      [debug] recipe=RecipeTest.Successful correlation_id=#{correlation_id} step=double assigns=%{number: 16}
      """

      assert capture_log(fn ->
        state = Recipe.empty_state
                |> Recipe.assign(:number, 4)

        Recipe.run(Successful, state, log_steps: true,
                                      correlation_id: correlation_id)
      end) == expected_log
    end
  end
end
