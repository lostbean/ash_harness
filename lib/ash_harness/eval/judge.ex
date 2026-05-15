defmodule AshHarness.Eval.Judge do
  @moduledoc """
  LLM-as-judge for `report :qualitative` blocks.

  The judge is invoked at most once per qualitative report. It receives
  the scenario's criteria (each with a free-form `:prompt`) plus the
  runtime context (trajectory + records) and returns a map of
  `criterion_name => score` where each score is a float in `[0.0, 1.0]`.

  The judge model is configured per-`Eval.Runner.run/2` call via the
  `:judge_model` option (string acceptable to `ReqLLM.generate_text/3`,
  e.g. `"anthropic:claude-sonnet-4-5"`). When no judge model is
  configured, the qualitative compute fn returns empty `scores` rather
  than calling this module — see `AshHarness.Eval`.

  The call goes through ReqLLM directly (the same stack `jido_composer`
  uses for LLM calls). HTTP options — including the `plug:` injection
  used by tests — flow through `:judge_req_options` and are passed to
  ReqLLM as `:req_http_options`.

  The judge prompt asks the model to respond with a single JSON object
  mapping criterion names to numeric scores. The parser tolerates a
  raw JSON object or a JSON object embedded in a fenced/inline code
  block; anything it can't decode yields an empty map and the report
  records nil scores.
  """

  @doc """
  Score `criteria` against the run context. Returns a map of
  `criterion_atom => number`. Unknown / malformed responses yield an
  empty map.
  """
  @spec score([map()], map(), String.t() | nil, keyword()) :: %{atom() => number()}
  def score(_criteria, _ctx, nil, _req_options), do: %{}

  def score(criteria, ctx, model, req_options) when is_binary(model) do
    prompt = build_prompt(criteria, ctx)

    opts =
      case req_options do
        nil -> []
        [] -> []
        list when is_list(list) -> [req_http_options: list]
      end

    # When the caller injected a Req `:plug` (stubbed LLM, e.g. in tests),
    # ReqLLM's key resolution still runs and raises if no API-key is
    # configured. Inject a sentinel `:api_key` so the plug actually
    # intercepts. Real callers without a plug fall through to normal
    # env-var / config resolution.
    opts =
      if stubbed_plug?(req_options) and not Keyword.has_key?(opts, :api_key) do
        Keyword.put(opts, :api_key, "stub-plug")
      else
        opts
      end

    case ReqLLM.generate_text(model, prompt, opts) do
      {:ok, response} ->
        text = ReqLLM.Response.text(response) || ""
        parse_scores(text, criteria)

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  # ----------------------------------------------------------------
  # Prompt construction
  # ----------------------------------------------------------------

  defp build_prompt(criteria, ctx) do
    trajectory_summary =
      inspect(ctx[:trajectory] || [], limit: 5, printable_limit: 200, pretty: true)

    state_summary =
      inspect(Map.drop(ctx || %{}, [:trajectory, :session]),
        limit: 5,
        printable_limit: 200,
        pretty: true
      )

    criteria_list =
      Enum.map_join(criteria, "\n", fn c ->
        "- #{c.name}: #{c.opts[:prompt] || "(no prompt)"}"
      end)

    """
    You are an evaluator. Score each criterion from 0.0 to 1.0 based on
    the agent's trajectory and the final state.

    Trajectory (truncated):
    #{trajectory_summary}

    Final state (truncated):
    #{state_summary}

    Criteria:
    #{criteria_list}

    Respond ONLY with a JSON object mapping criterion names to scores,
    e.g. {"name1": 0.8, "name2": 0.5}.
    """
  end

  # ----------------------------------------------------------------
  # Response parsing
  # ----------------------------------------------------------------

  defp parse_scores(text, criteria) do
    case decode_first_object(text) do
      {:ok, map} when is_map(map) -> atomize(map, criteria)
      _ -> %{}
    end
  end

  defp decode_first_object(text) do
    trimmed = String.trim(text)

    case Jason.decode(trimmed) do
      {:ok, map} when is_map(map) ->
        {:ok, map}

      _ ->
        # Try to extract a JSON object from a fenced code block or
        # inline text.
        case Regex.run(~r/\{(?:[^{}]|\\.)+\}/s, trimmed) do
          [json] -> Jason.decode(json)
          _ -> :error
        end
    end
  end

  defp stubbed_plug?(nil), do: false

  defp stubbed_plug?(opts) when is_list(opts) do
    Keyword.has_key?(opts, :plug)
  end

  defp stubbed_plug?(_), do: false

  # Convert string keys to atoms — but only atoms that already exist
  # (every criterion name has been declared at compile time, so its
  # atom exists by the time the judge runs).
  defp atomize(map, criteria) do
    known =
      Enum.into(criteria, %{}, fn c -> {Atom.to_string(c.name), c.name} end)

    Enum.reduce(map, %{}, fn {k, v}, acc ->
      case Map.fetch(known, to_string(k)) do
        {:ok, atom} -> Map.put(acc, atom, v)
        :error -> acc
      end
    end)
  end
end
