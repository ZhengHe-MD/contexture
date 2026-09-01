# Product definition

Status: working product contract, 2026-09-01

## Purpose

Contexture is a standalone, macOS-first Markdown writing editor. It combines a
raw Markdown source editor with a rendered preview and makes an intentional
source selection available to AI agents without embedding another chat box.

The writer remains free to start or continue conversations in the Agent Host
they already use. Contexture supplies writing context; it does not replace the
agent's conversation interface.

## Core contract

1. A writer opens a local Markdown Document and selects source text.
2. Contexture captures an immutable Selection Snapshot and visibly indicates
   that it is available for sharing.
3. When the writer submits a prompt in a compatible Agent Host, its Agent
   Adapter reads the current snapshot from the local Selection Bridge.
4. A current, non-empty snapshot becomes clearly delimited Selection Context
   for that turn.
5. A missing, empty, whitespace-only, expired, or already-consumed snapshot
   produces no injected context and does not alter the prompt.
6. Next Prompt snapshots are cleared only after successful Consumption. Pinned
   snapshots remain available until the writer clears them or the source is no
   longer valid.

The behavior in step 5 is an invariant, not a fallback. An unavailable
Contexture app or bridge is also a no-context condition: the Agent Host must
continue normally.

## Sharing modes

- **Off** — no Selection Context is made available.
- **Next Prompt** — the current Selection Snapshot may be consumed once. This
  is the safe default.
- **Pinned** — the current Selection Snapshot may be supplied to subsequent
  prompts until the writer clears it or Contexture invalidates it.

The editor must show the active mode and whether a snapshot is available, but
it does not need a conversation panel.

## Writing experience

- Use standard macOS window chrome and traffic-light placement.
- Keep the raw source and preview as a full-height split view; the divider runs
  continuously from the top of the content area to the bottom.
- Wrap long lines in the raw source pane instead of hiding content beyond the
  horizontal viewport.
- Keep opening, editing, previewing, saving, closing, and reopening ordinary
  Markdown files useful without any agent installation.
- Keep agent integration quiet when it is unused or unavailable.

## Privacy and safety

- Selection-only is the default disclosure boundary. Never expand an empty
  Selection to the whole Document.
- Treat selected Markdown as quoted, untrusted data rather than behavioral
  instructions.
- Disclose the selected text, target Agent Host, Sharing Mode, and any path or
  surrounding context before broader access is granted.
- Do not log Selection contents by default.
- Bind local services to a user-only local transport. If loopback HTTP is used,
  require an unguessable per-installation credential and reject non-local
  clients.
- Apply future agent edits as reviewable proposals against the captured
  document revision. The editor remains the authority over the live Document.

## Product boundaries

The first product should include:

- a native macOS Markdown editor;
- raw source plus rendered preview;
- local-file opening and safe autosave;
- Selection Snapshot capture and visible sharing state;
- the local Selection Bridge;
- deterministic adapters for hook-capable Agent Hosts;
- an MCP fallback for hosts without a context-injection hook;
- installation diagnostics and a clean uninstall path for every adapter.

The first product should not include:

- an embedded general-purpose chat interface;
- UI scripting or Accessibility automation that pastes into other apps;
- modification of vendor transcript files;
- silent whole-document, folder, shell, or network access;
- direct, unreviewed agent writes to the Document;
- a claim of deterministic support where only MCP or advisory skills exist.

## Distribution direction

The likely first distribution is a Developer ID-signed and notarized direct
download. Installing hooks and communicating with local agent CLIs is easier to
support outside the Mac App Store sandbox. App Store distribution remains a
later option after the helper and sandbox boundaries are proven.

Agent adapters may be installed separately. If an adapter or CLI is present
while the macOS app is absent or not running, it must fail open: return no
Selection Context, avoid modifying the prompt, and expose diagnostics only on
explicit request.

## Success criteria for the first integration release

- The same selected Markdown reaches at least three independently installed,
  hook-capable Agent Hosts.
- A prompt submitted with no Selection is byte-for-byte unchanged at the
  adapter's prompt boundary.
- Next Prompt content is injected at most once and cannot leak into a later
  prompt.
- Pinned content is withdrawn immediately when cleared or invalidated.
- Contexture remains a complete Markdown editor when no agent tooling is
  installed.
- Adapter latency is small enough that prompt submission does not feel delayed.

## Open product questions

- Should selecting text automatically arm Next Prompt, or should a small Share
  control be required?
- When a selection crosses Markdown blocks, should Contexture offer an explicit
  expansion to the containing heading section?
- Should paths be withheld by default and replaced with an app-scoped Document
  identifier?
- Which three Agent Hosts define the initial compatibility and release gate?
- What is the retention policy for pinned snapshots and adapter diagnostics?
- When edit proposals arrive, should the first write scope be replacement of
  the selected range only?

