---
status: accepted
date: 2026-09-01
---

# Keep agent conversations external

Contexture will remain a focused Markdown editor and make selected source
available through a local Selection Bridge plus Agent Adapters, rather than
embedding its own general-purpose chat interface. Prompt lifecycle hooks are
the primary integration because they can add current context deterministically;
MCP and skills remain fallbacks because they are pull-based or advisory. This
preserves the writer's existing Agent Host and keeps the editor visually clean,
at the cost of maintaining vendor-specific Adapters and reporting unequal
compatibility honestly.

## Considered options

- An editor-owned ACP or vendor-SDK conversation would provide the strongest
  portable session control, but it would require Contexture to become another
  chat client.
- Accessibility automation could paste into arbitrary apps, but it is brittle,
  invasive, and unable to prove which model context received the text.
- MCP-only integration is portable, but it cannot guarantee that the current
  selection is fetched on each task.

A second, independent reason reinforces this: most agent harnesses cannot be
built on. Codex is the notable exception. Even if that reading of the terms
turns out to be wrong, the product argument above stands on its own and the
decision does not change.

## Consequences

The Selection Bridge must fail open, return no context for every empty or
invalid selection state, and deduplicate hooks that fire more than once per
turn. A host without a context-mutating prompt hook is best-effort support, not
feature parity.

