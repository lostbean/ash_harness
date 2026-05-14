[
  # MapSet.new/0 is opaque; dialyzer flags struct-literal initializers
  # that include it as opaque-mismatches when passed to functions
  # spec'd to take the struct. The actual call is safe — we're
  # building the struct's own type.
  {"lib/ash_harness/harness.ex", :call_without_opaque},

  # `policy_gate.ex:42` and `schema.ex:78` reflect pre-existing
  # nil-fallback guards on values dialyzer can prove are non-nil
  # through their Ash callers. Harmless extra defensiveness; remove
  # in v0.2 once we've verified all call sites.
  {"lib/ash_harness/harness/policy_gate.ex", :guard_fail, 42},
  {"lib/ash_harness/schema.ex", :guard_fail, 78},

  # Defensive `rescue _ -> false` in sandbox helper guards against
  # Ash schema changes that aren't currently observable to dialyzer.
  {"lib/ash_harness/eval/sandbox.ex", :pattern_match}
]
