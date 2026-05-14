import Config

# Quiet the test suite: drop :debug / :info / :notice. Ash, Jido, and
# ReqLLM are chatty at those levels (action dispatch dumps, ETS writes,
# Telemetry's anonymous-handler nag). Tests that need to inspect log
# output should wrap their assertion in `ExUnit.CaptureLog.capture_log/1`
# instead of relying on the global stream.
config :logger, level: :warning
