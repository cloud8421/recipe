defmodule RecipeTest do
  use ExUnit.Case, async: true

  doctest Recipe

  defmodule Successful.Debug do
    def on_start(_state) do
      send(self(), :on_start)
    end

    def on_finish(_state) do
      send(self(), :on_finish)
    end

    def on_success(step, _state, _elapsed) do
      send(self(), {:on_success, step})
    end

    def on_error(_step, _error, _state, _elapsed) do
      send(self(), :on_error)
    end
  end

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

  defmodule Failing do
    use Recipe

    def steps, do: [:fail]

    def handle_result(state), do: state

    def handle_error(step, error, _state) do
      {step, error}
    end

    def fail(_state) do
      {:error, :not_magic_number}
    end
  end

  describe "Successful recipe run" do
    test "returns the final result" do
      state =
        Recipe.initial_state()
        |> Recipe.assign(:number, 4)

      assert {:ok, _correlation_id, 32} = Recipe.run(Successful, state)
    end

    test "it reuses a correlation id if passed" do
      correlation_id = Recipe.UUID.generate()

      state =
        Recipe.initial_state()
        |> Recipe.assign(:number, 4)

      assert {:ok, correlation_id, 32} ==
               Recipe.run(Successful, state, correlation_id: correlation_id)
    end
  end

  describe "Failing recipe run" do
    test "returns the desired error" do
      state =
        Recipe.initial_state()
        |> Recipe.assign(:number, 4)

      assert {:error, {:fail, {:error, :not_magic_number}}} == Recipe.run(Failing, state)
    end
  end

  describe "recipe state" do
    test "defaults" do
      state = Recipe.initial_state()

      assert state.telemetry_module == Recipe.Debug
      assert state.run_opts == [enable_telemetry: false]
    end
  end

  describe "telemetry support" do
    test "can use a custom telemetry module" do
      correlation_id = Recipe.UUID.generate()

      state =
        Recipe.initial_state()
        |> Recipe.assign(:number, 4)

      Recipe.run(
        Successful,
        state,
        enable_telemetry: true,
        telemetry_module: Successful.Debug,
        correlation_id: correlation_id
      )

      assert_receive :on_start
      assert_receive {:on_success, :square}
      assert_receive {:on_success, :double}
      assert_receive :on_finish
    end
  end

  describe "compile time warnings" do
    test "it checks for a valid steps/0 function" do
      assert_raise Recipe.InvalidRecipe, fn ->
        defmodule InvalidModule do
          use Recipe

          def handle_error(_, _, _), do: :ok
          def handle_result(_), do: :ok
        end
      end
    after
      :code.purge(RecipeTest.InvalidModule)
      :code.delete(RecipeTest.InvalidModule)
    end

    test "it checks for steps implementation" do
      assert_raise Recipe.InvalidRecipe, fn ->
        defmodule InvalidModule do
          use Recipe

          def steps, do: [:double]

          def handle_error(_, _, _), do: :ok
          def handle_result(_), do: :ok
        end
      end
    after
      :code.purge(RecipeTest.InvalidModule)
      :code.delete(RecipeTest.InvalidModule)
    end
  end
end
