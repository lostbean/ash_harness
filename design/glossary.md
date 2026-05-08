# Glossary

Pinned vocabulary for AshHarness design docs and code. When a doc uses a
term in this list, it means *exactly* this — not the LangChain meaning,
not the OpenAI Agents SDK meaning. If you find a doc using a term loosely,
fix it or add a note.

| Term | Meaning |
| --- | --- |
| **Agent** | A module that uses `AshHarness.Agent`. A behavioral declaration; not an Ash resource. Has identity, scope, behavior, delegation graph, constraints. |
| **Action** (Ash) | A named operation declared on an Ash resource — `:read`, `:create`, `:update`, `:destroy`, or generic. The unit of "doing" on a resource. |
| **Action** (Jido) | A `Jido.Action` module: a tool the orchestrator can call. AshHarness generates one per scoped Ash action. |
| **Actor** | Ash's authorization principal. Set on the agent's `identity` block. Every Ash call from the harness flows the actor through `Ash.can?` and the actual action. |
| **Anti-corruption boundary** | The text-only return contract for delegation. The calling agent never receives the delegate's raw records; only the delegate's natural-language reply. |
| **Annotation** | Metadata added to a resource via `AshHarness.Resource` or to a domain via `AshHarness.Domain`. Read by the context renderer; never alters Ash behavior. |
| **Canonical schema** | The single JSON-Schema-shaped artifact AshHarness derives at compile time per scoped action. Renderers project it to Anthropic, OpenAI, MCP. |
| **Confirmation flow** | The handshake when an agent attempts an action listed in `confirm_before`. Implemented via Jido's `ApprovalRequest` / `ApprovalResponse`. |
| **Diagnostic** | An eval metric that is reported but does *not* gate pass/fail (trajectory metrics, qualitative scores). |
| **Domain** (Ash) | An Ash umbrella that groups resources. Declares which resources exist and how they relate. |
| **Dynamic tool** | A tool created at session-start time via `AshHarness.Tool.dynamic/2` rather than at compile time. Used for session-scoped or context-conditional tools. |
| **Gate** | An eval assertion that *must* pass for the scenario to pass. Resource-state assertions are gates by default. |
| **Harness** | The runtime wrapper that mediates between Jido orchestrators and Ash. Enforces scope, runs `Ash.can?`, applies budgets, captures trajectory. |
| **Hidden attribute** | An attribute of a resource that the context renderer excludes from agent-visible context. Use for internal/sensitive fields. |
| **Hint** | A natural-language string attached to a specific action via `agent_annotations` `hint`. Tells the agent when/why to use that action. Becomes part of the tool description. |
| **Identity** | The `identity` block on an agent — name, description, actor. Determines who the agent is and whose authorization it uses. |
| **Intent** | A parsed model output: the agent's intention to invoke a specific (resource, action, input). Internal to the harness; users typically don't construct these directly. |
| **Jido Composer** | The agent runtime AshHarness builds on. Provides the orchestrator, skills, HITL, checkpointing, OTel spans. |
| **Mutation budget** | Per-turn cap on create/update/destroy actions, enforced by the harness. AshHarness-specific defense-in-depth. |
| **Orchestrator** | A `Jido.Composer.Orchestrator` — the LLM-driven loop. AshHarness wraps one per agent. |
| **Policy** (Ash) | An authorization rule on an Ash resource. AshHarness honors policies via `Ash.can?` at execution time. |
| **Progressive disclosure** | The pattern of starting with a small tool/context set and loading more on demand. Implemented via `Jido.Composer.Node.DynamicAgentNode` over per-resource `Skill`s. |
| **Reachability graph** | The traversable map of resources/relationships an agent can navigate, derived from scope + `traversable` annotations. |
| **Repair loop** | The retry-on-validation-failure pattern. When an Ash action fails validation, the harness can format the error and feed it back to the LLM. **Renamed from "Ralph Loop"** in the original spec. |
| **Resource** (Ash) | An Ash data type — attributes, relationships, actions, validations, policies. |
| **Scenario** | A unit of evaluation. Has a setup, a prompt, a set of gates, and a set of reports. |
| **Scope** | The agent's static declared capability set: which resources × which actions. Resources/actions outside scope are invisible (no tool generated) and unexecutable (harness rejects). |
| **Session** | A single conversational turn or run of an agent. Has an actor, a trajectory, mutation count, and inherits the agent's constraints. |
| **Skill** (Jido) | A `Jido.Composer.Skill` — a packaged bundle of `(name, description, prompt_fragment, tools)`. AshHarness generates one Skill per scoped Ash resource. |
| **Strategy** | A named approach declared in the `behavior` block. Becomes a hint in the system prompt. |
| **Trajectory** | The ordered log of actions taken in a session. Used by eval `report :trajectory` blocks and emitted via telemetry. |
| **Traversable** | A relationship listed in `agent_annotations.traversable`. Tells the reachability graph that this edge is allowed for agents. |

## Renames from the original spec

| Original | Now | Reason |
| --- | --- | --- |
| `AshAgent` (library) | `AshHarness` | User decision; library = `ash_harness` package; everything under `AshHarness.*`. |
| `AshAgent.*` modules | `AshHarness.*` | Single namespace. |
| `Ralph Loop` / `RalphLoop` | `Repair Loop` / `AshHarness.Harness.Repair` | Descriptive: the pattern repairs failed actions. |
| `assert_resource` (eval) | `gate :resource_state` | Make pass/fail semantics explicit. |
| `assert_trajectory` | `report :trajectory` | Trajectory is a diagnostic, not a gate. |
| `qualitative` | `report :qualitative` | Qualitative is a diagnostic, not a gate. |
| Composite weighted scoring | Gate + diagnostics | Per ADR 0002 (matches consensus practice). |
