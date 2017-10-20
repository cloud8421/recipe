defmodule Recipe.DebugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  @correlation_id Recipe.UUID.generate()
  @state %Recipe{correlation_id: @correlation_id, recipe_module: Example, assigns: %{number: 4}}

  test "on_start/1" do
    expected = """
    [debug] recipe=Example evt=start correlation_id=#{@correlation_id} assigns=%{number: 4}
    """

    assert capture_log(fn ->
             Recipe.Debug.on_start(@state)
           end) == expected
  end

  test "on_finish/1" do
    expected = """
    [debug] recipe=Example evt=end correlation_id=#{@correlation_id} assigns=%{number: 4}
    """

    assert capture_log(fn ->
             Recipe.Debug.on_finish(@state)
           end) == expected
  end

  test "on_success/3" do
    expected = """
    [debug] recipe=Example evt=step correlation_id=#{@correlation_id} step=square assigns=%{number: 4} duration=9
    """

    assert capture_log(fn ->
             Recipe.Debug.on_success(:square, @state, 9)
           end) == expected
  end

  test "on_error/4" do
    expected = """
    [error] recipe=Example evt=error correlation_id=#{@correlation_id} step=square error={:error, :less_than_5} assigns=%{number: 4} duration=2
    """

    assert capture_log(fn ->
             Recipe.Debug.on_error(:square, {:error, :less_than_5}, @state, 2)
           end) == expected
  end
end
