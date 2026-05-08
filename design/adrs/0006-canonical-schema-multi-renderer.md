# ADR 0006 — One canonical schema; multiple renderers

## Status

Accepted (2026-05-08).

## Context

Modern LLM/tool ecosystems all want JSON Schema, but in slightly
different envelopes:

- Anthropic Messages API: `tools[].input_schema` (JSON Schema 2020-12).
- OpenAI tool calling: `tools[].function.parameters`.
- MCP: tool's `inputSchema` (JSON Schema 2020-12 default), optional
  `outputSchema`.

The shapes are 95% the same; the wrappers differ.

## Decision

Derive one canonical schema artifact at compile time per scoped action
(`%AshHarness.Schema.Canonical{}`). Provide three pure renderers that
project to each format:

- `AshHarness.Schema.Render.Anthropic`
- `AshHarness.Schema.Render.OpenAI`
- `AshHarness.Schema.Render.MCP`

The harness uses the Anthropic-shaped output by default (because
`jido_composer` defaults to Anthropic via Jido AI). Other renderers are
exposed for users who export tool schemas independently (e.g., to mount
an MCP server in front of the same tool set).

## Consequences

### Pros

- One source of truth for tool schemas.
- New target formats are pure-function additions, not new derivation
  pipelines.
- MCP becomes a near-zero-cost addition (one renderer + a small
  router).

### Cons

- The canonical type is its own thing — users needing fine control
  over a specific format may need an escape hatch (TBD; v0.2).

### MCP exposure

v0.1.0 ships the renderer. **An actual MCP server** that mounts these
tools is out of scope for v0.1.0 (we don't want to re-implement
`hermes_mcp` or `ash_ai`'s MCP router). Users who want MCP exposure
today can wire the canonical schemas into their own router.

## Type mapping

See `layers/06-tool-generation.md` for the Ash → JSON-Schema mapping
table.

## Alternatives considered

1. **Anthropic-only artifact, no canonical.** Rejected — locks us into
   one provider's shape, makes future format support a refactor.
2. **JSON Schema as the canonical (no intermediate type).** Considered.
   Tradeoff: easier to write renderers, harder to attach
   AshHarness-specific metadata (hint references, originating action
   atom). Chose intermediate struct so we can carry that metadata.
3. **Per-format DSL extensions.** Rejected — over-engineered; the
   formats are too similar.
