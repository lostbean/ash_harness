defmodule AshHarness.Eval do
  @moduledoc """
  Declarative eval framework for AshHarness agents.

  `use AshHarness.Eval` gives a module the `scenario/2`, `agent/1`,
  `setup/1`, `prompt/1`, `gate/2`, and `report/2` macros. Scenarios
  pass iff all their gates pass; reports are diagnostic and never
  affect `result.passed`.
  """

  defmacro __using__(_opts) do
    quote do
      import AshHarness.Eval,
        only: [
          scenario: 2,
          agent: 1,
          setup: 1,
          prompt: 1,
          gate: 2,
          report: 2,
          auto_confirm: 1
        ]

      Module.register_attribute(__MODULE__, :ash_harness_scenario_names, accumulate: true)
      @before_compile AshHarness.Eval
    end
  end

  defmacro __before_compile__(env) do
    names = Module.get_attribute(env.module, :ash_harness_scenario_names) |> Enum.reverse()

    scenario_calls =
      for n <- names do
        fn_name = String.to_atom("__scenario_#{safe_name(n)}__")
        quote do: apply(__MODULE__, unquote(fn_name), [])
      end

    quote do
      def scenarios do
        unquote(scenario_calls)
      end
    end
  end

  @doc """
  Declare one scenario. Builds the scenario struct inline; gates and
  reports become anonymous functions captured at scenario-call time.
  """
  defmacro scenario(name, do: block) do
    fn_name = String.to_atom("__scenario_#{safe_name(name)}__")

    quote do
      @ash_harness_scenario_names unquote(name)

      def unquote(fn_name)() do
        # Defaults; user macros (agent/setup/prompt/auto_confirm/gate/report)
        # shadow these inside the block. The `_ = ...` pin marks each
        # default as used so the compiler doesn't warn when a scenario
        # overrides — without changing observable behavior.
        var!(ash_harness_agent) = nil
        _ = var!(ash_harness_agent)
        var!(ash_harness_setup) = fn -> %{} end
        _ = var!(ash_harness_setup)
        var!(ash_harness_prompt) = nil
        _ = var!(ash_harness_prompt)
        var!(ash_harness_gates) = []
        var!(ash_harness_reports) = []
        var!(ash_harness_auto_confirm) = nil
        _ = var!(ash_harness_auto_confirm)

        unquote(block)

        %AshHarness.Eval.Scenario{
          name: unquote(name),
          agent: var!(ash_harness_agent),
          setup: var!(ash_harness_setup),
          prompt: var!(ash_harness_prompt),
          gates: Enum.reverse(var!(ash_harness_gates)),
          reports: Enum.reverse(var!(ash_harness_reports)),
          auto_confirm: var!(ash_harness_auto_confirm)
        }
      end
    end
  end

  defmacro agent(module) do
    quote do
      var!(ash_harness_agent) = unquote(module)
    end
  end

  defmacro setup(fun_ast) do
    quote do
      var!(ash_harness_setup) = unquote(fun_ast)
    end
  end

  defmacro prompt(text) do
    quote do
      var!(ash_harness_prompt) = unquote(text)
    end
  end

  @doc """
  Per-scenario auto-confirm mode. Overrides any runner-level setting.
  Valid values are `:always_approve`, `:always_reject`, or
  `{:custom, fn intent -> :approved | :rejected end}`.
  """
  defmacro auto_confirm(mode) do
    quote do
      var!(ash_harness_auto_confirm) = unquote(mode)
    end
  end

  defmacro gate(:resource_state, do: block) do
    assertions_ast = AshHarness.Eval.__resource_state_block__(block)

    quote do
      var!(ash_harness_gates) = [
        %AshHarness.Eval.Gate{
          kind: :resource_state,
          check: fn ctx ->
            assertions = unquote(assertions_ast)

            Enum.map(assertions, fn {record_key, field, predicate} ->
              record = Map.get(ctx[:records] || %{}, record_key)
              actual = if is_map(record), do: Map.get(record, field), else: nil
              {{record_key, field}, predicate.(actual), actual}
            end)
          end
        }
        | var!(ash_harness_gates)
      ]
    end
  end

  defmacro gate(:invariant, do: block) do
    quote do
      var!(ash_harness_gates) = [
        %AshHarness.Eval.Gate{
          kind: :invariant,
          check: fn _ctx ->
            result = unquote(block)
            [{:invariant, !!result, result}]
          end
        }
        | var!(ash_harness_gates)
      ]
    end
  end

  defmacro report(:trajectory, do: block) do
    opts_ast = AshHarness.Eval.__trajectory_opts__(block)

    quote do
      var!(ash_harness_reports) = [
        %AshHarness.Eval.Report{
          kind: :trajectory,
          compute: fn ctx ->
            opts = unquote(opts_ast)
            trajectory = ctx[:trajectory] || []
            actions = length(trajectory)
            tokens = ctx[:tokens_used] || 0

            trajectory_actions = AshHarness.Eval.__trajectory_action_names__(trajectory)

            max_tokens = opts[:max_tokens]
            includes_seq = opts[:includes_sequence] || []
            excludes_list = opts[:excludes] || []

            %{
              actions: actions,
              max_actions: opts[:max_actions],
              max_actions_ok: actions <= (opts[:max_actions] || actions),
              tokens_used: tokens,
              max_tokens: max_tokens,
              max_tokens_ok: is_nil(max_tokens) or tokens <= max_tokens,
              includes_sequence: includes_seq,
              includes_sequence_ok:
                AshHarness.Eval.subsequence?(trajectory_actions, includes_seq),
              excludes: excludes_list,
              excludes_ok: not Enum.any?(trajectory_actions, fn a -> a in excludes_list end)
            }
          end
        }
        | var!(ash_harness_reports)
      ]
    end
  end

  defmacro report(:qualitative, do: block) do
    criteria_ast = AshHarness.Eval.__qualitative_criteria__(block)

    quote do
      var!(ash_harness_reports) = [
        %AshHarness.Eval.Report{
          kind: :qualitative,
          compute: fn ctx ->
            criteria = unquote(criteria_ast)
            AshHarness.Eval.__qualitative_compute__(criteria, ctx)
          end
        }
        | var!(ash_harness_reports)
      ]
    end
  end

  @doc false
  # Runtime helper for `report :qualitative`. Pulled out of the macro
  # so the judge wiring can be unit-tested directly and so changes
  # don't require recompiling every scenario module.
  def __qualitative_compute__(criteria, ctx) do
    judge_model =
      ctx[:judge_model] || Application.get_env(:ash_harness, :eval, [])[:judge_model]

    judge_req_options = ctx[:judge_req_options] || []

    scores =
      if judge_model do
        AshHarness.Eval.Judge.score(criteria, ctx, judge_model, judge_req_options)
      else
        %{}
      end

    observations =
      Enum.map(criteria, fn %{name: name, opts: opts} ->
        score = Map.get(scores, name)
        threshold = opts[:threshold]

        %{
          name: name,
          score: score,
          threshold: threshold,
          prompt: opts[:prompt],
          below_threshold?: is_number(score) and is_number(threshold) and score < threshold
        }
      end)

    %{criteria: criteria, scores: scores, observations: observations}
  end

  # ----------------------------------------------------------------
  # Trajectory report runtime helpers
  # ----------------------------------------------------------------

  @doc false
  # Extract normalized action names (e.g. :ticket_assign) from a
  # trajectory list. Each entry is expected to expose an `:intent` map
  # with `:resource` (module) and `:action` (atom). Entries without
  # both are skipped.
  def __trajectory_action_names__(trajectory) when is_list(trajectory) do
    trajectory
    |> Enum.map(&trajectory_entry_action_name/1)
    |> Enum.reject(&is_nil/1)
  end

  def __trajectory_action_names__(_), do: []

  defp trajectory_entry_action_name(%{intent: %{resource: r, action: a}})
       when not is_nil(r) and not is_nil(a) do
    short =
      r
      |> Module.split()
      |> List.last()
      |> Macro.underscore()
      |> String.to_atom()

    :"#{short}_#{a}"
  end

  defp trajectory_entry_action_name(_), do: nil

  @doc false
  # Returns true iff `needle` appears as an in-order (but not
  # necessarily contiguous) subsequence of `haystack`.
  def subsequence?(_haystack, []), do: true
  def subsequence?([], _needle), do: false
  def subsequence?([h | rest], [h | needle_rest]), do: subsequence?(rest, needle_rest)
  def subsequence?([_ | rest], needle), do: subsequence?(rest, needle)

  # ----------------------------------------------------------------
  # Block parsers (compile-time helpers)
  # ----------------------------------------------------------------

  @doc false
  def __resource_state_block__({:__block__, _, lines}), do: parse_assertions(lines)
  def __resource_state_block__(line), do: parse_assertions([line])

  defp parse_assertions(lines) do
    quoted =
      for line <- lines do
        case line do
          {:assert, _, [record, field, predicate]} ->
            quote do: {unquote(record), unquote(field), unquote(predicate)}

          other ->
            quote do: {nil, nil, fn _ -> !!unquote(other) end}
        end
      end

    quote do: unquote(quoted)
  end

  @doc false
  def __trajectory_opts__({:__block__, _, lines}), do: parse_kw_lines(lines)
  def __trajectory_opts__(line), do: parse_kw_lines([line])

  defp parse_kw_lines(lines) do
    quoted =
      for line <- lines do
        case line do
          {key, _, [value]} when is_atom(key) ->
            quote do: {unquote(key), unquote(value)}

          _ ->
            nil
        end
      end
      |> Enum.reject(&is_nil/1)

    quote do: unquote(quoted)
  end

  @doc false
  def __qualitative_criteria__({:__block__, _, lines}), do: parse_criteria(lines)
  def __qualitative_criteria__(line), do: parse_criteria([line])

  defp parse_criteria(lines) do
    quoted =
      for line <- lines do
        case line do
          {:criterion, _, [name, opts]} ->
            quote do: %{name: unquote(name), opts: unquote(opts)}

          _ ->
            nil
        end
      end
      |> Enum.reject(&is_nil/1)

    quote do: unquote(quoted)
  end

  @doc false
  def safe_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "_")
    |> String.trim("_")
  end
end
