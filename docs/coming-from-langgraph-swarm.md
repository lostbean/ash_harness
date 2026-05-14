# Coming from LangGraph / Swarm

If you've built agents with LangGraph or OpenAI's Swarm, here's the
mental-model map.

## What's the same

- Tools are first-class. LangGraph has tool nodes; AshHarness generates
  one `Jido.Action` module per scoped Ash action.
- Multi-agent: AshHarness supports delegation (one agent asking another
  for help, text-only reply).
- Eval-first: AshHarness ships a declarative eval framework with
  pass/fail gates and diagnostic reports.

## What's different

- **Tools come from your data layer**. Instead of writing tool
  functions, you declare Ash resources + actions and AshHarness emits
  the tools at compile time. The tool's schema is derived from the
  action's accepted parameters and arguments.
- **Authorization is enforced inside the tool**. AshHarness runs
  `Ash.can?` and the policy block before any Ash mutation. There's no
  separate "permissions middleware".
- **No custom LLM loop**. The runtime is `jido_composer`'s
  orchestrator. AshHarness intercepts via the generated `Jido.Action`'s
  `run/2` to enforce gates; the LLM loop itself is Jido's.
- **Delegation is text-only**. Compared to Swarm's structured handoffs,
  AshHarness delegations are deliberately conservative: the caller sees
  a string, not records.
- **Per-turn mutation budget**. AshHarness counts successful mutations
  per turn and refuses to exceed `max_mutations_per_turn`. Reads don't
  count; failed mutations don't count. ADR 0009.

## Quick map

| LangGraph / Swarm | AshHarness |
| --- | --- |
| `@tool` decorator | `actions [:foo, :bar]` in `scope` |
| Tool schema (Pydantic / JSON) | Derived from Ash action's `accept`/`arguments` |
| Authorization decorator | `Ash.can?` enforced inside generated tool |
| Conditional edges | `confirm_before [:foo]` + `auto_execute [:bar]` |
| Subgraph delegation | `delegates_to do delegate Other, "..." end` |
| Eval suite | `use AshHarness.Eval` |

See `design/architecture/coming-from-langgraph-swarm.md` for the long
form.
