# Agent compatibility for automatic Selection Context

Status: primary-source research snapshot, 2026-09-01

## Conclusion

Automatic, chat-free Selection Context is feasible when an Agent Host exposes a
deterministic prompt lifecycle hook that can add or rewrite model-visible
context. MCP and skills broaden reach but do not independently force the model
to read the current selection.

“Supported” here means a documented hook can run for the prompt or model call,
read the local Selection Bridge, and produce no context when the bridge returns
`none`. It does not mean an agent can discover another application's selection
without Contexture publishing it.

## Compatibility matrix

| Agent Host | Classification | Current integration seam |
| --- | --- | --- |
| OpenAI Codex | Deterministic | `UserPromptSubmit` can add `additionalContext` as developer context and supplies a turn ID. |
| Claude Code | Deterministic | `UserPromptSubmit` can add `additionalContext` alongside the submitted prompt. |
| Google Gemini CLI | Deterministic | `BeforeAgent` can add context to the prompt for the current turn. |
| GitHub Copilot CLI/SDK | Deterministic | `userPromptTransformed` can replace the model-facing prompt while leaving the displayed prompt unchanged. |
| Google Antigravity | Deterministic with deduplication | `PreInvocation` can inject an `ephemeralMessage`; it may fire multiple times in one turn, so the Adapter must deduplicate. |
| Cursor | Best effort | `beforeSubmitPrompt` can allow or block but cannot currently add context. MCP, rules, or session-start context are not equivalent to per-prompt injection. |
| Windsurf / Cascade | Best effort | Selection is integrated inside its own editor, but no documented external per-prompt injection seam was found. MCP remains pull-based. |
| Aider | CLI fallback | A new or owned CLI run can receive selected text, but no documented prompt hook or MCP client provides the same external-conversation behavior. |

## Neutral output is supported

Every deterministic Adapter can preserve an ordinary prompt when there is no
Selection:

- Codex, Claude Code, and Gemini CLI return successful hook output without an
  additional-context field.
- GitHub Copilot returns no `modifiedTransformedPrompt`.
- Antigravity returns an empty object or omits `injectSteps`.

Therefore the cross-agent contract is practical: `snapshot | none` maps to
“one context block | no hook mutation.”

## Agent-specific notes

### OpenAI Codex

Codex hooks can be installed globally, per repository, or through a plugin.
`UserPromptSubmit` receives the pending prompt and a Codex turn ID. Plain stdout
or `hookSpecificOutput.additionalContext` becomes extra developer context.
This is a direct per-turn Adapter seam.

Source: [Codex Hooks](https://learn.chatgpt.com/docs/hooks)

### Claude Code

Claude Code's `UserPromptSubmit` fires before the prompt is processed and can
return `additionalContext`. The injected text is model-visible without
appearing as a normal chat message. An empty successful result leaves the
prompt alone.

Source: [Claude Code Hooks](https://code.claude.com/docs/en/hooks)

### Gemini CLI

Gemini CLI's `BeforeAgent` fires after submission and before planning. Its
`hookSpecificOutput.additionalContext` is appended to the prompt for that turn
only, matching Contexture's Next Prompt semantics closely.

Source: [Gemini CLI Hooks](https://geminicli.com/docs/hooks/reference/)

### GitHub Copilot

Copilot's `userPromptTransformed` fires after runtime transformation and before
the model-facing content is sent and persisted. Returning
`modifiedTransformedPrompt` can append the Selection Context while keeping the
user-visible timeline prompt unchanged. Returning an empty result preserves the
original transformed prompt.

Source: [GitHub Copilot Hooks](https://docs.github.com/en/copilot/reference/hooks-reference)

### Google Antigravity

Antigravity's `PreInvocation` runs before each model call and may return
`injectSteps`, including an `ephemeralMessage`. When no snapshot exists, the
Adapter omits `injectSteps`. Because one user task can contain multiple model
invocations, Consumption must be keyed so the same selection is injected at
most once per user turn.

Antigravity plugins can bundle hooks and MCP configuration, providing a useful
single-package distribution path for the Adapter.

Sources: [Antigravity Hooks](https://www.antigravity.google/docs/hooks/),
[Antigravity Plugins](https://www.antigravity.google/docs/cli/plugins/),
[Antigravity MCP](https://antigravity.google/docs/mcp)

### Cursor

Cursor's documented `beforeSubmitPrompt` output supports `continue` and an
optional user-facing blocking message, not prompt replacement or additional
context. Cursor can inject at session start and can connect to MCP servers, but
neither guarantees a fresh Selection Snapshot on every submitted prompt.

Source: [Cursor Hooks](https://prod.cursor.com/docs/hooks)

## Why hooks, MCP, and skills are separate

- A **hook** runs at a lifecycle event and can deterministically attach current
  data when the host supports context mutation.
- An **MCP server** exposes a resource or tool. Whether it is fetched is still
  controlled by the host, user, or model unless a hook invokes it.
- A **skill** supplies reusable agent instructions. It can explain how to use
  Contexture, but following it is model behavior rather than an enforced
  per-prompt mechanism.
- **ACP or a vendor SDK** is valuable if Contexture later owns an agent
  conversation. It is not the primary seam for the chosen chat-free product.

## Certification requirement

Documentation establishes feasibility, not release compatibility. Each named
Agent Host must be tested on supported versions with a real installed Adapter,
including the shared empty-selection and deduplication cases. The app should
show “deterministic,” “best effort,” or “not installed” rather than flattening
these levels into one supported badge.

