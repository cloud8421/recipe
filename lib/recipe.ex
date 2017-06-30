defmodule Recipe do
  @moduledoc """
  ### Intro

  The `Recipe` module allows implementing multi-step, reversible workflows.

  For example, you may wanna parse some incoming data, write to two different data stores and
  then push some notifications. If anything fails, you wanna rollback specific changes in different
  data stores. `Recipe` allows you to do that.

  ### Core ideas

  - A workflow is a state machine
  - Each step can have a specific error handling scenario
  - Each step is a separate function that receives a state with the result of all previous steps

  ### Example

      defmodule Example do
        use Recipe

        ### Public API

        def run(number) do
          state = Recipe.empty_state
                  |> Recipe.assign(:number, number)

          Recipe.run(__MODULE__, state)
        end

        ### Callbacks

        def steps, do: [:square, :double]

        def handle_result(state) do
          {:ok, state.assigns.number}
        end

        def handle_error(_step, _error, _state), do: :cannot_fail

        ### Steps

        def square(state) do
          number = state.assigns.number
          {:ok, Recipe.assign(state, :number, number*number)}
        end

        def double(state) do
          number = state.assigns.number
          {:ok, Recipe.assign(state, :number, number * 2)}
        end
      end
  """

  alias Recipe.State

  @type step :: atom
  @type recipe_module :: atom
  @type error :: term

  @doc """
  Lists all steps included in the recipe, e.g. `[:square, :double]`
  """
  @callback steps() :: [step]

  @doc """
  Invoked at the end of the recipe, it receives the state obtained at the
  last step.
  """
  @callback handle_result(State.t) :: term
  @doc """
  Invoked any time a step fails. Receives the name of the failed step,
  the error and the state.
  """
  @callback handle_error(step, error, State.t) :: term

  defmodule InvalidRecipe do
    @moduledoc """
    This exception is raised whenever a module that implements the `Recipe`
    behaviour does not define a function definition for each listed step.
    """
    defexception [:message]
  end

  defmacro __using__(_opts) do
    quote do
      @behaviour Recipe

      @after_compile __MODULE__

      @doc false
      def __after_compile__(env, bytecode) do
        steps = __MODULE__.steps()
        definitions = Module.definitions_in(__MODULE__)

        case all_steps_defined?(definitions, steps) do
          :ok ->
            :ok
          {:missing, missing_steps} ->
            raise InvalidRecipe,
              message: "The recipe #{__MODULE__} misses step definitions for #{inspect missing_steps}"
        end
      end

      defp all_steps_defined?(definitions, steps) do
        missing_steps = Enum.filter(steps, fn(step) ->
                          :missing == Keyword.get(definitions, step, :missing)
                        end)

        case missing_steps do
          [] -> :ok
          _other -> {:missing, missing_steps}
        end
      end
    end
  end

  @doc """
  Returns an empty recipe state. Useful in conjunction with `Recipe.run/2`.
  """
  @spec empty_state() :: State.t
  def empty_state do
    %State{}
  end

  @doc """
  Assigns a new value in the recipe state under the specified key.

  Keys are available for reading under the `assigns` key.
  """
  @spec assign(State.t, atom, term) :: State.t
  def assign(state, key, value) do
    new_assigns = Map.put(state.assigns, key, value)
    %{state | assigns: new_assigns}
  end

  @doc """
  Runs a recipe, identified by a module which implements the `Recipe` behaviour.
  """
  @spec run(recipe_module) :: {:ok, term} | {:error, term}
  def run(recipe_module), do: run(recipe_module, empty_state())

  @doc """
  Runs a recipe, identified by a module which implements the `Recipe`
  behaviour, also allowing to specify the initial state.
  """
  @spec run(recipe_module, State.t) :: {:ok, term} | {:error, term}
  def run(recipe_module, initial_state) do
    steps = recipe_module.steps()

    do_run(steps, %{initial_state | recipe_module: recipe_module})
  end

  defp do_run([], state) do
    state.recipe_module.handle_result(state)
  end
  defp do_run([step | remaining_steps], state) do
    case apply(state.recipe_module, step, [state]) do
      {:ok, new_state} ->
        do_run(remaining_steps, new_state)
      error ->
        {:error, state.recipe_module.handle_error(step, error, state)}
    end
  end
end
