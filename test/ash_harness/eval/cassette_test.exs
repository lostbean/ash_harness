defmodule AshHarness.Eval.CassetteTest do
  use ExUnit.Case, async: false

  alias AshHarness.Eval.Cassette

  describe "cassette_path/2" do
    test "snake-cases the module and scenario name" do
      path = Cassette.cassette_path(AshHarness.Test.TriageAgent, "change flight")
      assert path =~ "test/cassettes/"
      assert String.ends_with?(path, "change_flight.json")
      assert path =~ "ash_harness_test_triage_agent"
    end

    test "different scenario names produce different file names" do
      a = Cassette.cassette_path(AshHarness.Test.TriageAgent, "scenario one")
      b = Cassette.cassette_path(AshHarness.Test.TriageAgent, "scenario two")
      refute a == b
    end
  end

  describe "mode/0" do
    test "defaults to :replay" do
      System.delete_env("ASH_HARNESS_CASSETTE_MODE")
      assert :replay = Cassette.mode()
    end

    test "honors :record" do
      System.put_env("ASH_HARNESS_CASSETTE_MODE", "record")
      assert :record = Cassette.mode()
      System.delete_env("ASH_HARNESS_CASSETTE_MODE")
    end

    test "honors :bypass" do
      System.put_env("ASH_HARNESS_CASSETTE_MODE", "bypass")
      assert :bypass = Cassette.mode()
      System.delete_env("ASH_HARNESS_CASSETTE_MODE")
    end

    test "raises on unknown values" do
      System.put_env("ASH_HARNESS_CASSETTE_MODE", "yolo")
      assert_raise ArgumentError, fn -> Cassette.mode() end
      System.delete_env("ASH_HARNESS_CASSETTE_MODE")
    end
  end
end
