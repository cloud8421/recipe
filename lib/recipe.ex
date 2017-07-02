defmodule Recipe do
  @moduledoc """
  ### Intro

  The `Recipe` module allows implementing multi-step, reversible workflows.

  For example, you may wanna parse some incoming data, write to two different
  data stores and then push some notifications. If anything fails, you wanna
  rollback specific changes in different data stores. `Recipe` allows you to do
  that.

  In addition, a recipe doesn't enforce any constraint around which processes
  execute which step. You can assume that unless you explicitly involve other
  processes, all code that builds a recipe is executed by default by the
  calling process.

  Ideal use cases are:

  - multi-step operations where you need basic transactional properties, e.g.
    saving data to Postgresql and Redis, rolling back the change in Postgresql if
    the Redis write fails
  - interaction with services that simply don't support transactions
  - composing multiple workflows that can share steps (with the
    help of `Kernel.defdelegate/2`)
  - trace workflows execution via a correlation id

  You can avoid using this library if:

  - A simple `with` macro will do
  - You don't care about failure semantics and just want your operation to
    crash the calling process
  - Using Ecto, you can express your workflow with `Ecto.Multi`

  Heavily inspired by the `ktn_recipe` module included in [inaka/erlang-katana](https://github.com/inaka/erlang-katana).

  ### Core ideas

  - A workflow as a set of discreet steps
  - Each step can have a specific error handling scenario
  - Each step is a separate function that receives a state
    with the result of all previous steps
  - Each step should be easily testable in isolation
  - Each workflow run is identified by a correlation id

  ### Example

  The example below outlines a possible workflow where a user creates a new
  conversation, passing an initial message.

  Each step is named in `steps/0`. Each step definition uses data added to the
  workflow state and performs a specific task.

  Any error shortcuts the workflow to `handle_error/3`, where a specialized
  clause for `:create_initial_message` deletes the conversation if the system
  failes to create the initial message (therefore simulating a transaction).

      defmodule StartNewConversation do
        use Recipe

        ### Public API

        def run(user_id, initial_message_text) do
          state = Recipe.initial_state
                  |> Recipe.assign(:user_id, user_id)
                  |> Recipe.assign(:initial_message_text, initial_message_text)

          Recipe.run(__MODULE__, state)
        end

        ### Callbacks

        def steps, do: [:validate,
                        :create_conversation,
                        :create_initial_message,
                        :broadcast_new_conversation,
                        :broadcast_new_message]

        def handle_result(state) do
          state.assigns.conversation
        end

        def handle_error(:create_initial_message, _error, state) do
          Service.Conversation.delete(state.conversation.id)
        end
        def handle_error(_step, error, _state), do: error

        ### Steps

        def validate(state) do
          text = state.assigns.initial_message_text
          if MessageValidator.valid_text?(text) do
            {:ok, state}
          else
            {:error, :empty_message_text}
          end
        end

        def create_conversation(state) do
          case Service.Conversation.create(state.assigns.user_id) do
            {:ok, conversation} ->
              {:ok, Recipe.assign(state, :conversation, conversation)}
            error ->
              error
          end
        end

        def create_initial_message(state) do
          %{user_id: user_id,
            conversation: conversation,
            initial_message_text: text} = state.assigns
          case Service.Message.create(user_id, conversation.id, text) do
            {:ok, message} ->
              {:ok, Recipe.assign(state, :initial_message, message)}
            error ->
              error
          end
        end

        def broadcast_new_conversation(state) do
          Dispatcher.broadcast("conversation-created", state.assigns.conversation)
          {:ok, state}
        end

        def broadcast_new_message(state) do
          Dispatcher.broadcast("message-created", state.assigns.initial_message)
          {:ok, state}
        end
      end
  """

  alias Recipe.UUID
  require Logger

  @default_run_opts [log_steps: false]

  defstruct assigns: %{},
            recipe_module: NoOp,
            correlation_id: nil,
            run_opts: @default_run_opts

  @type step :: atom
  @type recipe_module :: atom
  @type error :: term
  @type run_opts :: [{:log_steps, boolean} | {:correlation_id, UUID.t}]
  @type t :: %__MODULE__{assigns: %{},
                         recipe_module: module,
                         correlation_id: nil | Recipe.UUID.t,
                         run_opts: Recipe.run_opts}

  @doc """
  Lists all steps included in the recipe, e.g. `[:square, :double]`
  """
  @callback steps() :: [step]

  @doc """
  Invoked at the end of the recipe, it receives the state obtained at the
  last step.
  """
  @callback handle_result(t) :: term
  @doc """
  Invoked any time a step fails. Receives the name of the failed step,
  the error and the state.
  """
  @callback handle_error(step, error, t) :: term

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
        missing_steps = Enum.reduce(steps, [], fn(step, missing_steps) ->
          case Keyword.get(definitions, step, :not_defined) do
            :not_defined -> [step | missing_steps]
            arity when arity !== 1 -> [step | missing_steps]
            1 -> missing_steps
          end
        end)

        case missing_steps do
          [] -> :ok
          _other -> {:missing, Enum.reverse(missing_steps)}
        end
      end
    end
  end

  @doc """
  Returns an empty recipe state. Useful in conjunction with `Recipe.run/2`.
  """
  @spec initial_state() :: t
  def initial_state, do: %__MODULE__{}

  @doc """
  Assigns a new value in the recipe state under the specified key.

  Keys are available for reading under the `assigns` key.

      iex> state = Recipe.initial_state |> Recipe.assign(:user_id, 1)
      iex> state.assigns.user_id
      1
  """
  @spec assign(t, atom, term) :: t
  def assign(state, key, value) do
    new_assigns = Map.put(state.assigns, key, value)
    %{state | assigns: new_assigns}
  end

  @doc """
  Runs a recipe, identified by a module which implements the `Recipe`
  behaviour, allowing to specify the initial state.

  In case of a successful run, it will return a 3-element tuple `{:ok,
  correlation_id, result}`, where `correlation_id` is a uuid that can be used
  to connect this workflow with another one and `result` is the return value of
  the `handle_result/1` callback.

  Supports an optional third argument (a keyword list) for extra options:

  - `:log_steps`: when true, log (at debug level) each step with the updated state
  - `:correlation_id`: you can override the automatically generated correlation id
    by passing it as an option. A uuid can be generated with `Recipe.UUID.generate/0`

  ### Example

  ```
  Recipe.run(Workflow, Recipe.initial_state(), log_steps: true)
  ```
  """
  @spec run(recipe_module, t, run_opts) :: {:ok, UUID.t, term} | {:error, term}
  def run(recipe_module, initial_state, run_opts \\ []) do
    steps = recipe_module.steps()
    final_run_opts = Keyword.merge(initial_state.run_opts, run_opts)
    correlation_id = Keyword.get(run_opts, :correlation_id, UUID.generate())

    state = %{initial_state | recipe_module: recipe_module,
                              correlation_id: correlation_id,
                              run_opts: final_run_opts}

    do_run(steps, state)
  end

  defp do_run([], state) do
    {:ok, state.correlation_id, state.recipe_module.handle_result(state)}
  end
  defp do_run([step | remaining_steps], state) do
    maybe_log_step(step, state)
    case apply(state.recipe_module, step, [state]) do
      {:ok, new_state} ->
        do_run(remaining_steps, new_state)
      error ->
        {:error, state.recipe_module.handle_error(step, error, state)}
    end
  end

  defp maybe_log_step(step, state) do
    if Keyword.get(state.run_opts, :log_steps) do
      Logger.debug(fn() ->
        %{recipe_module: recipe,
          correlation_id: id,
          assigns: assigns} = state
        "recipe=#{inspect recipe} correlation_id=#{id} step=#{step} assigns=#{inspect assigns}"
      end)
    end
  end
end
