defmodule AshHarness.Test.LLMStub do
  @moduledoc """
  In-process Plug that returns a queue of pre-shaped Anthropic Messages
  API responses. Each invocation pops the front of the queue and writes
  it as the response body.

  ## Usage

      pid =
        LLMStub.start_link!([
          LLMStub.tool_use("ticket__assign", %{
            "id" => ticket.id,
            "assigned_to" => "alice",
            "reasoning" => "ok"
          }),
          LLMStub.text("Done.")
        ])

      session =
        Harness.new_session(MyAgent, req_options: [plug: {LLMStub, pid}])

  `req_options` is threaded by `OrchestratorFactory` into the
  orchestrator strategy state, then forwarded to `LLMAction`, which
  passes it to ReqLLM as `:req_http_options`. The Anthropic provider
  splats those options directly into `Req.new/1`, so `plug:` is
  honoured: the request never leaves the BEAM.

  Two builders are exposed:

    * `tool_use/3` — assistant message that emits a single `tool_use`
      content block. Stops with `stop_reason: "tool_use"`.
    * `text/2`    — assistant message with a single `text` block.
      Stops with `stop_reason: "end_turn"` (final answer).

  Once the queue is exhausted, every subsequent call returns a
  benign "(stub exhausted)" text response so the suite never hangs on
  network IO.
  """

  use Agent

  @typedoc "An Anthropic Messages API response body (decoded)."
  @type response :: map()

  @spec start_link!([response()]) :: pid()
  def start_link!(responses) when is_list(responses) do
    {:ok, pid} = Agent.start_link(fn -> responses end)
    pid
  end

  # ----------------------------------------------------------------
  # Plug callbacks
  # ----------------------------------------------------------------

  @doc false
  def init({pid, _opts}) when is_pid(pid), do: pid
  def init(pid) when is_pid(pid), do: pid
  def init(opts) when is_list(opts), do: Keyword.fetch!(opts, :pid)

  @doc false
  def call(conn, pid) do
    response =
      Agent.get_and_update(pid, fn
        [head | rest] -> {head, rest}
        [] -> {nil, []}
      end)

    body = response || exhausted_response()

    conn
    |> Plug.Conn.put_resp_header("content-type", "application/json")
    |> Plug.Conn.send_resp(200, Jason.encode!(body))
  end

  @doc """
  Returns the responses currently queued (for assertions in tests).
  """
  @spec pending(pid()) :: [response()]
  def pending(pid), do: Agent.get(pid, & &1)

  # ----------------------------------------------------------------
  # Response builders
  # ----------------------------------------------------------------

  @doc """
  Build a `tool_use` Anthropic Messages response.

  Options:
    * `:id` — message id (default: generated)
    * `:tool_use_id` — content block id (default: generated)
    * `:model` — model id (default: `"claude-sonnet-4-5-20250929"`)
  """
  @spec tool_use(String.t(), map(), keyword()) :: response()
  def tool_use(tool_name, input, opts \\ []) when is_binary(tool_name) and is_map(input) do
    %{
      "id" => Keyword.get(opts, :id, "msg_#{unique()}"),
      "type" => "message",
      "role" => "assistant",
      "model" => Keyword.get(opts, :model, "claude-sonnet-4-5-20250929"),
      "content" => [
        %{
          "type" => "tool_use",
          "id" => Keyword.get(opts, :tool_use_id, "toolu_#{unique()}"),
          "name" => tool_name,
          "input" => input
        }
      ],
      "stop_reason" => "tool_use",
      "stop_sequence" => nil,
      "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
    }
  end

  @doc """
  Build a final-answer text response.
  """
  @spec text(String.t(), keyword()) :: response()
  def text(content, opts \\ []) when is_binary(content) do
    %{
      "id" => Keyword.get(opts, :id, "msg_#{unique()}"),
      "type" => "message",
      "role" => "assistant",
      "model" => Keyword.get(opts, :model, "claude-sonnet-4-5-20250929"),
      "content" => [%{"type" => "text", "text" => content}],
      "stop_reason" => "end_turn",
      "stop_sequence" => nil,
      "usage" => %{"input_tokens" => 100, "output_tokens" => 50}
    }
  end

  # ----------------------------------------------------------------
  # Internal
  # ----------------------------------------------------------------

  defp exhausted_response do
    %{
      "id" => "msg_exhausted",
      "type" => "message",
      "role" => "assistant",
      "model" => "claude-sonnet-4-5-20250929",
      "content" => [%{"type" => "text", "text" => "(stub exhausted)"}],
      "stop_reason" => "end_turn",
      "stop_sequence" => nil,
      "usage" => %{"input_tokens" => 0, "output_tokens" => 0}
    }
  end

  defp unique, do: Integer.to_string(System.unique_integer([:positive]))
end
