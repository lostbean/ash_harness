[
  # MapSet.new/0 is opaque; dialyzer flags struct-literal initializers
  # that include it as opaque-mismatches when passed to functions
  # spec'd to take the struct. The actual call is safe — we're
  # building the struct's own type.
  {"lib/ash_harness/harness.ex", :call_without_opaque},

  # Defensive `response.data || %{}` fallback against
  # `%Jido.Composer.HITL.ApprovalResponse{}` whose `data` field is
  # spec'd as `map() | nil`. Through our call graph dialyzer infers
  # a non-nil map and flags the guard, but we keep the nil-fallback
  # because external hosts construct ApprovalResponses too.
  {"lib/ash_harness/harness.ex", :guard_fail, 340},
  {"lib/ash_harness/harness.ex", :guard_fail, 388},

  # `Ash.can?` may rescue to `:maybe` in the policy_gate; we then
  # treat `_` as the catch-all denial path even though Dialyzer can
  # see we exhaustively cover `%Ash.Error.Forbidden{}` through our
  # specific clauses. Kept for defence in depth.
  {"lib/ash_harness/harness/policy_gate.ex", :guard_fail, 91},
  {"lib/ash_harness/harness/policy_gate.ex", :pattern_match_cov},

  # Pre-existing nil-fallback guard on `action.arguments` — through
  # Ash's `Ash.Resource.Info.action/2` callers we always see a list
  # but the spec on `arguments` is `[map()] | nil`, so we keep the
  # `|| []` defensiveness.
  {"lib/ash_harness/schema.ex", :guard_fail, 78},

  # Defensive `rescue _ -> false` in sandbox helper guards against
  # Ash schema changes that aren't currently observable to dialyzer.
  {"lib/ash_harness/eval/sandbox.ex", :pattern_match}
]
