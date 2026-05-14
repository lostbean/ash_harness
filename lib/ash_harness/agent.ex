defmodule AshHarness.Agent do
  @moduledoc """
  Declares an AshHarness agent. Use it like:

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

        constraints do
          max_mutations_per_turn 10
          require_reasoning_for [:assign]
        end
      end

  The required `domains:` option lists the Ash domains whose resources
  this agent may scope. Compile-time verifiers reject scoped resources
  that don't belong to one of those domains.

  See `AshHarness.Agent.Info` for the introspection surface.
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshHarness.Agent.Dsl]],
    opt_schema: [
      domains: [
        type: {:list, :module},
        required: true,
        doc: "Ash domains whose resources this agent may scope."
      ]
    ]

  @impl Spark.Dsl
  def handle_opts(opts) do
    domains = Keyword.fetch!(opts, :domains)

    quote do
      @ash_harness_domains unquote(domains)
      @persist {:ash_harness_domains, unquote(domains)}
      @persist {:ash_harness_agent?, true}

      def __ash_harness_agent__?, do: true
      def __ash_harness_domains__, do: @ash_harness_domains
    end
  end
end
