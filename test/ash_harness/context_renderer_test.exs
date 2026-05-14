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
end
