[
  # Defensive `response.data || %{}` fallback against
  # `%Jido.Composer.HITL.ApprovalResponse{}` whose `data` field is
  # spec'd as `map() | nil`. Through our call graph dialyzer infers
  # a non-nil map and flags the guard, but we keep the nil-fallback
  # because external hosts construct ApprovalResponses too.
  {"lib/ash_harness/harness.ex", :guard_fail, 340},
  {"lib/ash_harness/harness.ex", :guard_fail, 388},

  # Defensive `input || %{}` nil-fallback on the `Ash.can?` call.
  # Through our call graph Dialyzer infers a non-nil map for `input`
  # and flags the guard, but external callers may construct intents
  # with a nil input, so we keep the fallback.
  {"lib/ash_harness/harness/policy_gate.ex", :guard_fail, 90},

  # Pre-existing nil-fallback guard on `action.arguments` — through
  # Ash's `Ash.Resource.Info.action/2` callers we always see a list
  # but the spec on `arguments` is `[map()] | nil`, so we keep the
  # `|| []` defensiveness.
  {"lib/ash_harness/schema.ex", :guard_fail, 78},

  # Defensive `rescue _ -> false` in sandbox helper guards against
  # Ash schema changes that aren't currently observable to dialyzer.
  {"lib/ash_harness/eval/sandbox.ex", :pattern_match}
]
