defmodule Recipe.State do
  @moduledoc false

  @default_debug_opts [log_steps: false]

  defstruct assigns: %{},
            recipe_module: NoOp,
            debug_opts: @default_debug_opts

  @type t :: %__MODULE__{assigns: %{},
                         recipe_module: module,
                         debug_opts: Recipe.debug_opts}
end
