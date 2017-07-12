defmodule Recipe.UUID do
  @moduledoc """
  UUID v4 generator, used for recipe correlation uuid(s).

  Credit goes to: from https://github.com/zyro/elixir-uuid/blob/master/lib/uuid.ex
  """

  @type t :: String.t

  @spec generate() :: t
  @doc """
  Generates a new v4 correlation uuid.
  """
  def generate do
    <<u0::48, _::4, u1::12, _::2, u2::62>> = :crypto.strong_rand_bytes(16)
    <<u0::48, 4::4, u1::12, 2::2, u2::62>>
    |> uuid_to_string()
  end

  defp uuid_to_string(<<u0::32, u1::16, u2::16, u3::16, u4::48>>) do
    [binary_to_hex_list(<<u0::32>>), ?-, binary_to_hex_list(<<u1::16>>), ?-,
     binary_to_hex_list(<<u2::16>>), ?-, binary_to_hex_list(<<u3::16>>), ?-,
     binary_to_hex_list(<<u4::48>>)]
     |> IO.iodata_to_binary
  end
  defp uuid_to_string(_u) do
    raise ArgumentError, message:
    "Invalid binary data; Expected: <<uuid::128>>"
  end

  defp binary_to_hex_list(binary) do
    :binary.bin_to_list(binary)
      |> list_to_hex_str
  end

  defp list_to_hex_str([]) do
    []
  end
  defp list_to_hex_str([head | tail]) do
    to_hex_str(head) ++ list_to_hex_str(tail)
  end

  defp to_hex_str(n) when n < 256 do
    [to_hex(div(n, 16)), to_hex(rem(n, 16))]
  end

  defp to_hex(i) when i < 10 do
    0 + i + 48
  end
  defp to_hex(i) when i >= 10 and i < 16 do
    ?a + (i - 10)
  end
end
