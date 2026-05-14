# `capture_log: true` routes all Logger output through ExUnit's
# per-test capture. Logs from passing tests are dropped; failing tests
# replay their captured logs in the failure report. Combined with the
# :warning level set in config/test.exs, the suite runs near-silent.
ExUnit.start(exclude: [:integration], capture_log: true)

Application.ensure_all_started(:ash)
