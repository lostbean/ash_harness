defmodule AshHarness do
  @moduledoc """
  AshHarness — turn Ash resources and domains into the operating layer
  for AI agents driven by `jido_composer`.

  ## What this is

  AshHarness lets you declare an *agent* whose understanding of what it
  can do is derived from the same Ash resource definitions and policies
  that enforce what it's allowed to do. One source of truth.

  Given an Ash resource and a `use AshHarness.Agent` declaration, the
  library generates:

    * a `Jido.Action` module per scoped action (the tool surface),
    * a `Jido.Composer.Skill` per scoped resource (progressive disclosure),
    * a canonical schema artifact that renders to Anthropic, OpenAI, and MCP,
    * a runtime gate pipeline (scope, reasoning, confirmation, budget, policy)
      that runs *inside* the generated tool, before any Ash mutation.

  See the `design/` folder in this repository for the architecture, ADRs,
  layer specs, and benchmark plan. `design/README.md` is the canonical
  entry point.

  ## Getting started

  Quickstart lives in the project README. The rough shape:

      defmodule MyApp.Ticket do
        use Ash.Resource,
          domain: MyApp.Ticketing,
          extensions: [AshHarness.Resource]

        agent_annotations do
          description "A unit of work in the support queue."
          traversable [:project]
          hidden_attributes [:internal_notes]
          hint :assign, "Use this to delegate work to a teammate."
        end
        # ... attributes, actions, policies
      end

      defmodule MyApp.TriageAgent do
        use AshHarness.Agent, domains: [MyApp.Ticketing]

        identity do
          name "TriageBot"
          description "Triages incoming support tickets."
          actor &MyApp.bot_actor/0
        end

        scope do
          resource MyApp.Ticket do
            actions [:read, :open_ticket, :assign]
          end
        end

        behavior do
          confirm_before [:assign]
          auto_execute [:read, :open_ticket]
        end
      end

      {:ok, session} = AshHarness.Harness.new_session(MyApp.TriageAgent)
      {:ok, reply, session} = AshHarness.Harness.run(session, "Hello")

  See `AshHarness.Agent`, `AshHarness.Resource`, `AshHarness.Domain`, and
  `AshHarness.Harness` for the full public API.
  """

  @doc """
  Returns the current AshHarness version.
  """
  @spec version() :: String.t()
  def version, do: Application.spec(:ash_harness, :vsn) |> to_string()
end
