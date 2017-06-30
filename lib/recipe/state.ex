defmodule Recipe.State do
  @moduledoc false

  defstruct assigns: %{},
            recipe_module: NoOp

  @type t :: %__MODULE__{assigns: %{},
                         recipe_module: module}
end
