defmodule AshHarnessTest do
  use ExUnit.Case
  doctest AshHarness

  test "greets the world" do
    assert AshHarness.hello() == :world
  end
end
