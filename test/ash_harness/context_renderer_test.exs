defmodule AshHarness.ContextRendererTest do
  use ExUnit.Case, async: true

  alias AshHarness.ContextRenderer
  alias AshHarness.RenderedContext
  alias AshHarness.Test.Ticket
  alias AshHarness.Test.TriageAgent

  test "render/2 returns a RenderedContext struct" do
    assert %RenderedContext{} = ctx = ContextRenderer.render(TriageAgent, cache?: false)
    assert is_binary(ctx.initial_text)
    assert ctx.token_estimate > 0
    assert is_map(ctx.resource_details)
  end

  test "initial text contains identity name and resource summaries" do
    ctx = ContextRenderer.render(TriageAgent, cache?: false)
    assert ctx.initial_text =~ "TriageBot"
    assert ctx.initial_text =~ "Ticket"
  end

  test "initial text excludes full per-resource detail" do
    ctx = ContextRenderer.render(TriageAgent, cache?: false)
    # The full attribute listing should not be in initial_text
    refute ctx.initial_text =~ "## Attributes"
  end

  test "render_resource/3 omits hidden_attributes" do
    text = ContextRenderer.render_resource(TriageAgent, Ticket)
    refute text =~ "internal_notes"
  end

  test "render_resource/3 includes scoped action hints" do
    text = ContextRenderer.render_resource(TriageAgent, Ticket)
    assert text =~ "Use this to delegate the ticket"
  end

  test "render_resource/3 marks action policy indicators" do
    text = ContextRenderer.render_resource(TriageAgent, Ticket)
    assert text =~ "(requires confirmation)"
    assert text =~ "(requires reasoning)"
  end

  test "render_resource/3 excludes out-of-scope actions" do
    text = ContextRenderer.render_resource(TriageAgent, Ticket)
    refute text =~ "**:resolve**"
    refute text =~ "**:destroy**"
  end

  test "token_budget truncation drops strategies first" do
    full = ContextRenderer.render(TriageAgent, cache?: false)

    # Budget tight enough to drop strategies but big enough to keep summaries
    budget = full.token_estimate - 2

    ctx =
      ContextRenderer.render(TriageAgent,
        cache?: false,
        token_budget: budget
      )

    # Resource summaries must remain
    assert ctx.initial_text =~ "Ticket"
  end

  test "render/2 with cache?: false runs fresh each time" do
    ctx1 = ContextRenderer.render(TriageAgent, cache?: false)
    ctx2 = ContextRenderer.render(TriageAgent, cache?: false)
    assert ctx1.initial_text == ctx2.initial_text
  end

  test "default cache returns same value across calls" do
    ctx1 = ContextRenderer.render(TriageAgent)
    ctx2 = ContextRenderer.render(TriageAgent)
    assert ctx1 == ctx2
  end

  describe "telemetry" do
    alias AshHarness.Test.TriageAgent

    setup do
      handler_id = "ctx-rendered-#{System.unique_integer()}"
      parent = self()

      :telemetry.attach(
        handler_id,
        [:ash_harness, :context, :rendered],
        fn _evt, measurements, metadata, _ ->
          send(parent, {:rendered, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)
      :ok
    end

    test "render/2 emits [:ash_harness, :context, :rendered] with token_estimate and cache_hit?: false on first call" do
      _ = AshHarness.ContextRenderer.render(TriageAgent, actor: %{id: "u1"})

      assert_receive {:rendered, measurements, metadata}
      assert measurements.token_estimate > 0
      assert measurements.cache_hit? == false
      assert is_integer(measurements.render_time_ms)
      assert measurements.render_time_ms >= 0
      assert is_integer(measurements.sections_count)
      assert measurements.sections_count > 0
      assert metadata.agent == TriageAgent
    end

    test "render/2 emits with cache_hit?: true on second identical call" do
      actor = %{id: "u1"}
      _ = AshHarness.ContextRenderer.render(TriageAgent, actor: actor)

      # Drain the first event
      assert_receive {:rendered, _, _}

      # Second call should be a cache hit
      _ = AshHarness.ContextRenderer.render(TriageAgent, actor: actor)
      assert_receive {:rendered, measurements, _}
      assert measurements.cache_hit? == true
      assert is_integer(measurements.render_time_ms)
      assert measurements.render_time_ms >= 0
      assert is_integer(measurements.sections_count)
      assert measurements.sections_count > 0
    end
  end
end
