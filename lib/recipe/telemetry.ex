defmodule Recipe.Telemetry do
  @moduledoc """
  The `Recipe.Telemetry` behaviour can be used to define
  a module capable of handling events emitted by a recipe
  run.

  Each callback is invoked at different step of a recipe run, receiving
  data about the current step and its execution time.

  Please refer to the docs for `Recipe.run/3` to see how to
  enable debug and telemetry information.
  """

  @type elapsed_microseconds :: integer()

  @doc """
  Invoked at the start of a recipe execution.
  """
  @callback on_start(Recipe.t) :: :ok

  @doc """
  Invoked at the end of a recipe execution, irrespectively of
  the success or failure of the last executed step.
  """
  @callback on_finish(Recipe.t) :: :ok

  @doc """
  Invoked after successfully executing a step.
  """
  @callback on_success(Recipe.step, Recipe.t, elapsed_microseconds) :: :ok

  @doc """
  Invoked after failing to execute a step.
  """
  @callback on_error(Recipe.step, term, Recipe.t, elapsed_microseconds) :: :ok

  defmacro __using__(_opts) do
    quote do
      @behaviour Recipe.Telemetry
    end
  end
end
