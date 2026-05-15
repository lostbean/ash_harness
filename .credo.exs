%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/",
          "benchmarks/"
        ],
        excluded: [
          ~r"/_build/",
          ~r"/deps/",
          ~r"^benchmarks/.*/deps/"
        ]
      },
      strict: true,
      checks: [
        # Defaults
        {Credo.Check.Readability.ModuleDoc, []},
        {Credo.Check.Readability.LargeNumbers, []},
        {Credo.Check.Refactor.CyclomaticComplexity, max_complexity: 12},
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Design.TagTODO, false},

        # Three-level deep functions are commonplace in DSL builders and
        # Spark verifier callbacks; allow up to 3.
        {Credo.Check.Refactor.Nesting, max_nesting: 3},

        # `apply/3` is occasionally necessary for module-call dispatch
        # against runtime-determined modules (eg. test telemetry handlers,
        # cross-package extension hooks). Keep the rule advisory only.
        {Credo.Check.Refactor.Apply, false},

        # length/1 in tests is fine — readability beats micro-optimization.
        {Credo.Check.Warning.ExpensiveEmptyEnumCheck, false},

        # Tightenings appropriate to this codebase:
        {Credo.Check.Warning.IExPry, []},
        {Credo.Check.Warning.IoInspect, []},

        # Disable the consistency-check on exception names. The check's
        # heuristic picks the lexically-first prefix it sees as the
        # canonical strategy; with two `Delegation*` errors in the set
        # it then flags every other `AshHarness.Errors.<Verb>` exception
        # (the standard suffix-only naming) as inconsistent. The actual
        # naming convention here — verb/noun suffix under
        # `AshHarness.Errors.*` — is exactly what `Splode` expects.
        {Credo.Check.Consistency.ExceptionNames, false}
      ]
    }
  ]
}
