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
  - Each workflow needs to be easily audited via logs or an event store

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

  ### Telemetry

  A recipe run can be instrumented with callbacks for start, end and each step execution.

  To instrument a recipe run, it's sufficient to call:

      Recipe.run(module, initial_state, enable_telemetry: true)

  The default setting for telemetry is to use the `Recipe.Debug` module, but you can implement
  your own by using the `Recipe.Telemetry` behaviour, definining the needed callbacks and run
  the recipe as follows:

      Recipe.run(module, initial_state, enable_telemetry: true, telemetry_module: MyModule)

  An example of a compliant module can be:

      defmodule Recipe.Debug do
        use Recipe.Telemetry

        def on_start(state) do
          IO.inspect(state)
        end

        def on_finish(state) do
          IO.inspect(state)
        end

        def on_success(step, state, elapsed_microseconds) do
          IO.inspect([step, state, elapsed_microseconds])
        end

        def on_error(step, error, state, elapsed_microseconds) do
          IO.inspect([step, error, state, elapsed_microseconds])
        end
      end

  ### Application-wide telemetry configuration

  If you wish to control telemetry application-wide, you can do that by
  creating an application-specific wrapper for `Recipe` as follows:

      defmodule MyApp.Recipe do
        def run(recipe_module, initial_state, run_opts \\ []) do
          final_run_opts = Keyword.put_new(run_opts,
                                           :enable_telemetry,
                                           telemetry_enabled?())

          Recipe.run(recipe_module, initial_state, final_run_opts)
        end

        def telemetry_on! do
          Application.put_env(:recipe, :enable_telemetry, true)
        end

        def telemetry_off! do
          Application.put_env(:recipe, :enable_telemetry, false)
        end

        defp telemetry_enabled? do
          Application.get_env(:recipe, :enable_telemetry, false)
        end
      end

  This module supports using a default setting which can be toggled
  at runtime with `telemetry_on!/0` and `telemetry_off!/0`, overridable
  on a per-run basis by passing `enable_telemetry: false` as a third
  argument to `MyApp.Recipe.run/3`.

  You can also add static configuration to `config/config.exs`:

      config :recipe,
        enable_telemetry: true
  """

  alias Recipe.{InvalidRecipe, UUID}
  require Logger

  @default_run_opts [enable_telemetry: false]

  defstruct assigns: %{},
            recipe_module: NoOp,
            correlation_id: nil,
            telemetry_module: Recipe.Debug,
            run_opts: @default_run_opts

  @type step :: atom
  @type recipe_module :: atom
  @type error :: term
  @type run_opts :: [{:enable_telemetry, boolean} | {:correlation_id, UUID.t()}]
  @type function_name :: atom
  @type telemetry_module :: module
  @type t :: %__MODULE__{
          assigns: %{optional(atom) => term},
          recipe_module: module,
          correlation_id: nil | Recipe.UUID.t(),
          telemetry_module: telemetry_module,
          run_opts: Recipe.run_opts()
        }

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

  defmacro __using__(_opts) do
    quote do
      @behaviour Recipe

      @after_compile __MODULE__

      @doc false
      def __after_compile__(env, bytecode) do
        unless Module.defines?(__MODULE__, {:steps, 0}) do
          raise InvalidRecipe, message: InvalidRecipe.missing_steps(__MODULE__)
        end

        steps = __MODULE__.steps()
        definitions = Module.definitions_in(__MODULE__)

        case all_steps_defined?(definitions, steps) do
          :ok ->
            :ok

          {:missing, missing_steps} ->
            raise InvalidRecipe,
              message: InvalidRecipe.missing_step_definitions(__MODULE__, missing_steps)
        end
      end

      defp all_steps_defined?(definitions, steps) do
        missing_steps =
          Enum.reduce(steps, [], fn step, missing_steps ->
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
  Unassigns (a.k.a. deletes) a specific key in the state assigns.

      iex> state = Recipe.initial_state |> Recipe.assign(:user_id, 1)
      iex> state.assigns.user_id
      1
      iex> new_state = Recipe.unassign(state, :user_id)
      iex> new_state.assigns
      %{}
  """
  @spec unassign(t, atom) :: t
  def unassign(state, key) do
    new_assigns = Map.delete(state.assigns, key)
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

  - `:enable_telemetry`: when true, uses the configured telemetry module to log
    and collect metrics around the recipe execution
  - `:telemetry_module`: the telemetry module to use when logging events and metrics.
    The module needs to implement the `Recipe.Telemetry` behaviour (see related docs),
    it's set by default to `Recipe.Debug` and it's only used when `:enable_telemetry`
    is set to true
  - `:correlation_id`: you can override the automatically generated correlation id
    by passing it as an option. A uuid can be generated with `Recipe.UUID.generate/0`

  ### Example

  ```
  Recipe.run(Workflow, Recipe.initial_state(), enable_telemetry: true)
  ```
  """
  @spec run(recipe_module, t, run_opts) :: {:ok, UUID.t(), term} | {:error, term}
  def run(recipe_module, initial_state, run_opts \\ []) do
    steps = recipe_module.steps()
    final_run_opts = Keyword.merge(initial_state.run_opts, run_opts)
    correlation_id = Keyword.get(final_run_opts, :correlation_id, UUID.generate())

    telemetry_module =
      Keyword.get(final_run_opts, :telemetry_module, initial_state.telemetry_module)

    state = %{
      initial_state
      | recipe_module: recipe_module,
        correlation_id: correlation_id,
        telemetry_module: telemetry_module,
        run_opts: final_run_opts
    }

    maybe_on_start(state)
    do_run(steps, state)
  end

  defp do_run([], state) do
    maybe_on_finish(state)
    {:ok, state.correlation_id, state.recipe_module.handle_result(state)}
  end

  defp do_run([step | remaining_steps], state) do
    case :timer.tc(state.recipe_module, step, [state]) do
      {elapsed, {:ok, new_state}} ->
        maybe_on_success(step, new_state, elapsed)
        do_run(remaining_steps, new_state)

      {elapsed, error} ->
        maybe_on_error(step, error, state, elapsed)
        {:error, state.recipe_module.handle_error(step, error, state)}
    end
  end

  defp maybe_on_start(state) do
    if Keyword.get(state.run_opts, :enable_telemetry) do
      state.telemetry_module.on_start(state)
    end
  end

  defp maybe_on_success(step, state, elapsed) do
    if Keyword.get(state.run_opts, :enable_telemetry) do
      state.telemetry_module.on_success(step, state, elapsed)
    end
  end

  defp maybe_on_error(step, error, state, elapsed) do
    if Keyword.get(state.run_opts, :enable_telemetry) do
      state.telemetry_module.on_error(step, error, state, elapsed)
    end
  end

  defp maybe_on_finish(state) do
    if Keyword.get(state.run_opts, :enable_telemetry) do
      state.telemetry_module.on_finish(state)
    end
  end
end
