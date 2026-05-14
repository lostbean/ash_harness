defmodule AshHarnessTest do
  use ExUnit.Case, async: true

  test "version is a string" do
    assert is_binary(AshHarness.version())
  end
end
