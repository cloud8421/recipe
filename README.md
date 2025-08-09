# Recipe

## Intro

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

## Core ideas

- A workflow is as a set of discreet steps
- Each step can have a specific error handling scenario
- Each step is a separate function that receives a state
  with the result of all previous steps
- Each step should be easily testable in isolation
- Each workflow needs to be easily audited via logs or an event store

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `recipe` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:recipe, "~> 0.4.0"}]
end
```

## Example

The example below outlines a possible workflow where a user creates a new
conversation, passing an initial message.

Each step is named in `steps/0`. Each step definition uses data added to the
workflow state and performs a specific task.

Any error shortcuts the workflow to `handle_error/3`, where a specialized
clause for `:create_initial_message` deletes the conversation if the system
failes to create the initial message (therefore simulating a transaction).

```elixir
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
```

For more examples, see: <https://github.com/cloud8421/recipe/tree/master/examples>.

## Telemetry

A recipe run can be instrumented with callbacks for start, end and each step execution.

To instrument a recipe run, it's sufficient to call:

```elixir
Recipe.run(module, initial_state, enable_telemetry: true)
```

The default setting for telemetry is to use the `Recipe.Debug` module, but you can implement
your own by using the `Recipe.Telemetry` behaviour, definining the needed callbacks and run
the recipe as follows:

```elixir
Recipe.run(module, initial_state, enable_telemetry: true, telemetry_module: MyModule)
```

An example of a compliant module can be:

```elixir
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
```

## Application-wide telemetry configuration

If you wish to control telemetry application-wide, you can do that by
creating an application-specific wrapper for `Recipe` as follows:

```elixir
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
```

This module supports using a default setting which can be toggled
at runtime with `telemetry_on!/0` and `telemetry_off!/0`, overridable
on a per-run basis by passing `enable_telemetry: false` as a third
argument to `MyApp.Recipe.run/3`.

You can also add static configuration to `config/config.exs`:

```elixir
config :recipe,
  enable_telemetry: true
```

## Type specifications

If you use type specifications via Dialyzer, you can extend the types defined
by Recipe to have better guarantees around your individual steps.

In the example below specifications and types are added for steps and values
inside assigns, so that it's possible for Dialyzer to provide more accurate results.

```elixir
defmodule Recipe.Example do
  @moduledoc false

  use Recipe

  @type step :: :double
  @type steps :: [step]
  @type assigns :: %{number: integer}
  @type state :: %Recipe{assigns: assigns}

  @spec run(integer) :: {:ok, integer} | {:error, :not_an_integer}
  def run(number) do
    initial_state = Recipe.initial_state
                    |> Recipe.assign(:number, number)

    Recipe.run(__MODULE__, initial_state)
  end

  def steps, do: [:double]

  @spec double(state) :: {:ok, state} | {:error, :not_an_integer}
  def double(state) do
    if is_integer(state.assigns.number) do
      {:ok, Recipe.assign(state, :number, state.assigns.number * 2)}
    else
      {:error, :not_an_integer}
    end
  end

  @spec handle_error(step, term, state) :: :ok
  def handle_error(_step, error, _state), do: error

  @spec handle_result(state) :: :ok
  def handle_result(_state), do: :ok
end
```

## Development/Test

- Initial setup can be done with `mix deps.get`
- Run tests with `mix test`
- Run dialyzer with `mix dialyzer`
- Run credo with `mix credo`
- Build docs with `mix docs`

## Special thanks

Special thanks go to the following people for their help in the initial design phase for this library:

- Ju Liu ([@arkham](https://github.com/Arkham))
- Emanuel Mota ([@emanuel](https://github.com/emanuel))
- Miguel Pinto ([@firewalkr](https://github.com/firewalkr))
