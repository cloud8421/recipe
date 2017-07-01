defmodule Recipe.State do
  @moduledoc false

  @default_run_opts [log_steps: false]

  defstruct assigns: %{},
            recipe_module: NoOp,
            correlation_id: nil,
            run_opts: @default_run_opts

  @type t :: %__MODULE__{assigns: %{},
                         recipe_module: module,
                         correlation_id: nil | Recipe.UUID.t,
                         run_opts: Recipe.run_opts}
end
