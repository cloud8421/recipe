# Recipe

[![Build Status](https://travis-ci.org/cloud8421/recipe.svg?branch=master)](https://travis-ci.org/cloud8421/recipe)

## Intro

The `Recipe` module allows implementing multi-step, reversible workflows.

For example, you may wanna parse some incoming data, write to two different data stores and
then push some notifications. If anything fails, you wanna rollback specific changes in different
data stores. `Recipe` allows you to do that.

Heavily inspired by the `ktn_recipe` module included in [inaka/erlang-katana](https://github.com/inaka/erlang-katana).

## Core ideas

- A workflow is a state machine
- Each step can have a specific error handling scenario
- Each step is a separate function that receives a state with the result of all previous steps

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `recipe` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:recipe, "~> 0.1.0"}]
end
```

## Example

```elixir
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
```

## Development/Test

- Initial setup can be done with `mix deps.get`
- Run tests with `mix test`
- Run dialyzer with `mix dialyzer`
- Run credo with `mix credo`
