defmodule Recipe.InvalidRecipe do
  @moduledoc """
  This exception is raised whenever a module that implements the `Recipe`
  behaviour does not define a function definition for each listed step.
  """
  defexception [:message]

  @doc false
  def missing_steps(recipe_module) do
    """

        #{IO.ANSI.red}
        The recipe #{inspect recipe_module} doesn't define
        the steps to execute.

        To fix this, you need to define a steps/0 function.

        For example:

        def steps, do: [:validate, :save]#{IO.ANSI.default_color}
    """
  end

  @doc false
  def missing_step_definitions(recipe_module, missing_steps) do
    [example_step | _rest] = missing_steps

    """

        #{IO.ANSI.red}
        The recipe #{inspect recipe_module} doesn't have step definitions
        for the following functions:

        #{inspect missing_steps}

        To fix this, you need to add the relevant
        function definitions. For example:

        def #{example_step}(state) do
          # your code here
          {:ok, new_state}
        end#{IO.ANSI.default_color}
    """
  end
end
