defmodule AshHarness.ContextRenderer.TokenEstimate do
  @moduledoc """
  Cheap token estimator. Defaults to `ceil(byte_size(text) / ratio)`
  where `ratio` is configurable via `config :ash_harness, :context,
  token_ratio: 4`.
  """

  @default_ratio 4

  @spec estimate(String.t() | iodata()) :: non_neg_integer()
  def estimate(text) when is_binary(text) do
    ratio = config_ratio()
    div(byte_size(text) + ratio - 1, ratio)
  end

  def estimate(iodata), do: estimate(IO.iodata_to_binary(iodata))

  defp config_ratio do
    Application.get_env(:ash_harness, :context, [])
    |> Keyword.get(:token_ratio, @default_ratio)
  end
end
