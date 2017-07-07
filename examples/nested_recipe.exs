defmodule NestedRecipe do
  @moduledoc """
  This example shows a recipe which uses another recipe
  to perform error handling.

  In the example below, the `Build` recipe kicks off
  a `Rollback` recipe when it's not possible to complete
  a successful build (i.e. the rolled out version doesn't start
  properly).

  Note also that the `Rollback` recipe uses some steps defined in
  `Build` via `defdelegate/2`.
  """

  defmodule Build do
    use Recipe

    def steps, do: [:clone_repo,
                    :run_build,
                    :create_new_revision,
                    :replace_revision,
                    :restart_service,
                    :remove_temp_files]

    def clone_repo(state) do
      %{repo_url: repo_url,
        app_name: app_name,
        revision: revision} = state

      case VCS.clone(app_name, repo_url, revision) do
        {:ok, build_path} ->
          {:ok, Recipe.assign(state, :build_path, build_path)}
        error ->
          error
      end
    end

    def run_build(state) do
      %{build_path: build_path} = state

      case BuildRunner.run(build_path) do
        {:ok, artifact} ->
          {:ok, Recipe.assign(state, :artifact, artifact)}
        error ->
          error
      end
    end

    def create_new_revision(state) do
      %{app_name: app_name,
        artifact: artifact} = state

      case Slug.package(app_name, artifact) do
        {:ok, revision_number, slug_url} ->
          new_state = state
                      |> Recipe.assign(:revision_number, revision_number)
                      |> Recipe.assign(:slug_url, slug_url)
          {:ok, new_state}
        error ->
          error
      end
    end

    def replace_revision(state) do
      %{app_name: app_name,
        revision_number: revision_number,
        slug_url: slug_url} = state

      case Revision.rollout(app_name, revision_number, slug_url) do
        :ok -> {:ok, state}
        error -> error
      end
    end

    def restart_service(state) do
      %{app_name: app_name} = state

      case Service.restart(app_name) do
        :ok -> {:ok, state}
        error -> error
      end
    end

    def remove_temp_files(state) do
      %{build_path: build_path} = state

      case BuildRunner.cleanup(build_path) do
        :ok -> {:ok, state}
        error -> error
      end
    end

    def handle_result(state) do
      {:deployed, state.assigns.app, state.assigns.revision_number}
    end

    def handle_error(:restart_service, _error, state) do
      Recipe.run(Rollback, state)
    end
    def handle_error(_step, _error, _state), do: {:error, :build_failed}
  end

  defmodule Rollback do
    use Recipe

    def steps, do: [:get_previous_revision,
                    :replace_revision,
                    :restart_service]

    def get_previous_revision(state) do
      %{app_name: app_name,
        revision_number: revision_number} = state

      case Revision.get_previous(app_name, revision_number) do
        {:ok, previous_revision, slug_url} ->
          new_state = state
                      |> Recipe.assign(:revision_number, previous_revision)
                      |> Recipe.assign(:slug_url, slug_url)
          {:ok, new_state}
        error ->
          error
      end
    end

    defdelegate replace_revision(state), to: CI
    defdelegate restart_service(state), to: CI

    def handle_result(state) do
      {:rolled_back, state.assigns.app, state.assigns.revision_numver}
    end

    def handle_error(_step, _error, _state) do
      raise "Failed to rollback we're all doomed"
    end
  end
end
