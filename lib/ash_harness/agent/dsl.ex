defmodule AshHarness.Agent.Dsl do
  @moduledoc """
  Spark DSL extension for `AshHarness.Agent`. Defines the `identity`,
  `scope`, `behavior`, `delegates_to`, and `constraints` sections.

  Don't use this module directly — instead, declare an agent with
  `use AshHarness.Agent, domains: [...]`.
  """

  # ----------------------------------------------------------------
  # identity
  # ----------------------------------------------------------------

  @identity %Spark.Dsl.Section{
    name: :identity,
    describe: """
    The agent's identity card: name, description, actor, and optional
    model. The actor may be a struct (passed through), a 0-arity
    function (called at session start), or an `{module, function, args}`
    tuple (applied at session start).
    """,
    examples: [
      """
      identity do
        name "TriageBot"
        description "Triages incoming support tickets."
        actor &MyApp.bot_actor/0
        model "anthropic:claude-sonnet-4-5"
      end
      """
    ],
    schema: [
      name: [type: :string, required: true, doc: "The agent's name."],
      description: [
        type: :string,
        required: true,
        doc: "Short description shown to the LLM."
      ],
      actor: [
        type: :any,
        required: true,
        doc: "Actor struct, 0-arity function, or `{module, function, args}` tuple."
      ],
      model: [
        type: {:or, [:string, nil]},
        default: nil,
        doc: "Optional model identifier (e.g. `\"anthropic:claude-sonnet-4-5\"`)."
      ]
    ]
  }

  # ----------------------------------------------------------------
  # scope
  # ----------------------------------------------------------------

  @resource_entry %Spark.Dsl.Entity{
    name: :resource,
    describe: """
    Allow the agent to invoke specific actions on a resource.
    """,
    examples: [
      """
      resource MyApp.Ticket do
        actions [:read, :open_ticket, :assign]
      end
      """
    ],
    target: AshHarness.Agent.Scope.ResourceEntry,
    args: [:module],
    schema: [
      module: [
        type: :module,
        required: true,
        doc: "Resource module."
      ],
      actions: [
        type: {:list, :atom},
        required: true,
        doc: "Actions on this resource the agent is permitted to invoke."
      ]
    ]
  }

  @scope %Spark.Dsl.Section{
    name: :scope,
    describe: """
    Resources and actions the agent is permitted to invoke. Must be
    non-empty.
    """,
    examples: [
      """
      scope do
        resource MyApp.Ticket do
          actions [:read, :open_ticket, :assign]
        end
      end
      """
    ],
    entities: [@resource_entry]
  }

  # ----------------------------------------------------------------
  # behavior
  # ----------------------------------------------------------------

  @strategy %Spark.Dsl.Entity{
    name: :strategy,
    describe: "A named strategy hint for the agent's planner.",
    examples: [~s|strategy :default, "Always read before writing."|],
    target: AshHarness.Agent.Behavior.Strategy,
    args: [:name, :description],
    schema: [
      name: [type: :atom, required: true, doc: "Strategy name."],
      description: [
        type: :string,
        required: true,
        doc: "What this strategy tells the agent to do."
      ]
    ]
  }

  @behavior_section %Spark.Dsl.Section{
    name: :behavior,
    describe: """
    Per-action policy: which actions need confirmation, which auto-execute,
    and zero or more named strategies.
    """,
    examples: [
      """
      behavior do
        confirm_before [:assign, :destroy]
        auto_execute [:read]
        strategy :default, "Read before writing."
      end
      """
    ],
    schema: [
      confirm_before: [
        type: {:list, :atom},
        default: [],
        doc: "Actions that require human confirmation before executing."
      ],
      auto_execute: [
        type: {:list, :atom},
        default: [],
        doc: "Actions that execute without confirmation."
      ]
    ],
    entities: [@strategy]
  }

  # ----------------------------------------------------------------
  # delegates_to
  # ----------------------------------------------------------------

  @delegate %Spark.Dsl.Entity{
    name: :delegate,
    describe: "Allow this agent to delegate questions to another agent.",
    examples: [
      ~s|delegate MyApp.AccountAgent, as: "accounts", purpose: "Customer-account questions."|
    ],
    target: AshHarness.Agent.Delegation.DelegateEntry,
    args: [:agent_module],
    schema: [
      agent_module: [
        type: :module,
        required: true,
        doc: "Target agent module (must use `AshHarness.Agent`)."
      ],
      as: [
        type: :string,
        required: true,
        doc:
          "Short, case-insensitive alias the LLM uses to refer to this delegate " <>
            "(e.g. `\"billing\"`)."
      ],
      purpose: [
        type: :string,
        required: true,
        doc: "Description of when to delegate to this agent."
      ]
    ]
  }

  @delegates_to %Spark.Dsl.Section{
    name: :delegates_to,
    describe: """
    Other agents this agent may delegate to. Each target must itself be
    an AshHarness agent module.
    """,
    examples: [
      """
      delegates_to do
        delegate MyApp.AccountAgent, as: "accounts", purpose: "Customer-account questions."
      end
      """
    ],
    entities: [@delegate]
  }

  # ----------------------------------------------------------------
  # constraints
  # ----------------------------------------------------------------

  @constraints %Spark.Dsl.Section{
    name: :constraints,
    describe: """
    Operating limits: per-turn mutation budget, list of actions that
    require an explicit `reasoning` argument, max context tokens, and
    repair-loop retry cap.
    """,
    examples: [
      """
      constraints do
        max_mutations_per_turn 10
        require_reasoning_for [:assign, :destroy]
        max_context_tokens 128_000
        max_repair_loop_retries 3
      end
      """
    ],
    schema: [
      max_mutations_per_turn: [
        type: :non_neg_integer,
        default: 10,
        doc: "Successful mutations allowed per turn (reads don't count)."
      ],
      require_reasoning_for: [
        type: {:list, :atom},
        default: [],
        doc: "Actions that require an LLM-supplied `reasoning` string."
      ],
      max_context_tokens: [
        type: :non_neg_integer,
        default: 128_000,
        doc: "Max estimated tokens for the rendered initial context."
      ],
      max_repair_loop_retries: [
        type: :non_neg_integer,
        default: 3,
        doc: "Max repair-loop retry attempts per (resource, action)."
      ]
    ]
  }

  use Spark.Dsl.Extension,
    sections: [@identity, @scope, @behavior_section, @delegates_to, @constraints],
    transformers: [
      AshHarness.Agent.Transformers.ComputeReachability,
      AshHarness.Agent.Transformers.ComputeToolSet,
      AshHarness.Agent.Transformers.EmitTools
    ],
    verifiers: [
      AshHarness.Agent.Verifiers.ScopeNotEmpty,
      AshHarness.Agent.Verifiers.ScopeResourcesInDomains,
      AshHarness.Agent.Verifiers.ScopeActionsExist,
      AshHarness.Agent.Verifiers.ConfirmBeforeInScope,
      AshHarness.Agent.Verifiers.AutoExecuteInScope,
      AshHarness.Agent.Verifiers.ConfirmAutoMutuallyExclusive,
      AshHarness.Agent.Verifiers.ReasoningActionsInScope,
      AshHarness.Agent.Verifiers.DelegatesUseAshHarnessAgent,
      AshHarness.Agent.Verifiers.DelegateAliasesUnique,
      AshHarness.Agent.Verifiers.DomainTermsNoConflict,
      AshHarness.Agent.Verifiers.ToolNamesUnique
    ]
end
