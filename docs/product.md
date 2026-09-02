# Product definition

Status: working product contract, 2026-09-01

## Purpose

Contexture is a standalone, macOS-first editor for text formats that have a
rendered representation. It combines a raw Source editor with a Preview and
makes an intentional Source Selection available to AI agents without embedding
another chat box.

The writer remains free to start or continue conversations in the Agent Host
they already use. Contexture supplies writing context; it does not replace the
agent's conversation interface.

Markdown is the first supported Document format. A fenced Source block whose
first info-string token is `mermaid` renders as a static Diagram inside that
Markdown Preview; this does not make standalone Mermaid files a second
Document format. HTML, SVG, and standalone Mermaid are the natural next ones.
Formats with nothing to render — JSON, source code — are out of scope; editors
already own them.

## Audience

A writer who also hand-authors markup: an article with custom layout, a landing
page, an email template. Not an application developer. Optimising for the
app-building case would mean competing with established IDEs on their own
ground while giving up the one real advantage here — a clean writing
environment with an ambient agent seam.

## Core contract

1. A writer opens a local Document and selects Source text, in either pane.
2. Contexture captures an immutable Selection Snapshot, Arms it, and visibly
   indicates that it is available.
3. When the writer submits a prompt in a compatible Agent Host, its Agent
   Adapter reads the Armed snapshots in scope from the local Selection Bridge.
4. Each current, non-empty snapshot becomes a clearly delimited Selection
   Context block for that turn.
5. A missing, empty, whitespace-only, stale, out-of-scope, or already-consumed
   snapshot produces no injected context and does not alter the prompt.
6. Next Prompt snapshots are cleared only after successful Consumption.

The behavior in step 5 is an invariant, not a fallback. An unavailable
Contexture app or bridge is also a no-context condition: the Agent Host must
continue normally.

## Arming

Selecting is sharing. There is no separate share gesture.

Arming survives the visible Selection collapsing, so clicking elsewhere to fix
a typo does not silently withdraw the context. A snapshot stays Armed until it
is superseded by a new Selection in that Document, consumed, cleared, its
Document closes, or its revision changes. There is no clock expiry.

Because a snapshot can be Armed with nothing highlighted, the window shows a
persistent count of Armed snapshots and offers a single-key clear.

## Sharing modes

- **Off** — no Selection Context is made available.
- **Next Prompt** — an Armed snapshot may be consumed once. This is the
  default.
- **Pinned** — deferred. Its invalidation rules are the most complex lifetime
  logic in the design, and automatic Arming makes re-Arming nearly free, which
  removes most of its motivation. It earns its complexity only if daily use
  shows writers re-selecting the same passage repeatedly.

## Writing experience

- Use standard macOS window chrome and traffic-light placement.
- Keep the Source and Preview as a full-height split view; the divider runs
  continuously from the top of the content area to the bottom.
- Keep leading YAML front matter in the Source but omit it from the Preview.
  When it contains a non-empty string `title`, show that title in the native
  window chrome; otherwise use the Document's filename.
- Wrap long lines in the Source pane instead of hiding content beyond the
  horizontal viewport.
- Show the Selection in both panes simultaneously. A Preview selection snaps
  outward to complete nodes so that published bytes stay parseable.
- Render Mermaid Blocks as atomic Preview nodes. Size each Diagram to its
  content up to the Preview width and half the Preview viewport height. When
  either limit reduces it, make it a keyboard-accessible zoom target that
  opens an app-level viewer with fit/zoom controls; closing the viewer returns
  the writer to the same place. A Preview Selection touching a Diagram snaps
  to the whole fenced block; opening its viewer does not Arm it.
- Follow macOS light/dark appearance when rendering a Diagram. Safe visual
  Mermaid configuration may override presentation, but never Contexture's
  security or resource limits.
- Keep opening, editing, previewing, saving, closing, and reopening ordinary
  files useful without any agent installation.
- Keep agent integration quiet when it is unused or unavailable.

## Privacy and safety

- Selection-only is the default disclosure boundary. Never expand an empty
  Selection to the whole Document.
- Return only Documents under the Agent Host's Working Root. Contexture never
  reveals a location the agent could not already reach.
- Disclose paths relative to the Working Root, never absolute.
- Treat selected Source as quoted, untrusted data rather than behavioral
  instructions.
- Do not log Selection contents by default.
- Bind local services to a user-only Unix domain socket at mode `0600`.
- Render the Preview so its Document content cannot execute scripts or
  make remote loads (see ADR-0002 for the isolation mechanism — Source and
  Preview share one web view, so this holds even though that view's
  JavaScript is not literally disabled overall).
- Render Mermaid Source only with the bundled, pinned renderer in the trusted
  outer editor page. Insert only a sanitized, inert SVG data image into the
  script-free Preview; Diagram Source may not enable callbacks, links, remote
  resources, or weaker Mermaid security settings.

## Document authority

The filesystem is the authority over a Document, not the editor. Agent Hosts
write files with their own tools, and Contexture is not in that loop.

Publishing a snapshot flushes the buffer to disk first, so a revision hash
always describes on-disk content and doubles as a conflict detector. Contexture
watches each open Document: an external write reloads a clean buffer and raises
a conflict on a dirty one. A Document with no path cannot publish.

Reviewable edit proposals remain desirable, but they would require Contexture
to mediate writes it does not currently see. They are not part of the first
release.

## Product boundaries

The first product should include:

- a native macOS editor shell around a CodeMirror 6 editor and Preview;
- Source plus rendered Preview with synchronized Selection;
- static rendering of lowercase `mermaid` fenced blocks, with an accessible
  name and a local inline error for invalid Diagram Source;
- local-file opening, safe autosave, and flush-on-publish;
- Selection Snapshot capture, Arming, and visible sharing state;
- the local Selection Bridge over a Unix domain socket;
- deterministic adapters for Codex, Claude Code, and Antigravity;
- the shared black-box test harness, built after the first adapter and
  before the second and third — a conformance target has nothing to test
  against until one real adapter exists, and earns its keep precisely where
  a second and third are about to land together;
- installation diagnostics and a clean uninstall path for every adapter.

The first product should not include:

- an embedded general-purpose chat interface;
- Pinned sharing mode;
- a format plugin API or registry;
- reviewable edit proposals;
- UI scripting or Accessibility automation that pastes into other apps;
- modification of vendor transcript files;
- silent whole-document, folder, shell, or network access;
- a claim of deterministic support where only MCP or advisory skills exist.

## Extensibility posture

Multi-format support is preserved by exactly three cheap commitments: the
glossary does not say Markdown, the envelope carries a format tag from the
first release, and document plumbing is not welded to a single file type.

No format abstraction is built until a second Document format exists. Mermaid
Blocks are a Markdown Preview feature, not a second format. A plugin system, a
format registry, or a provider protocol with one implementation is an
abstraction designed against a single example, and the second example is what
teaches where the seam belongs.

## Distribution direction

Developer ID-signed and notarized direct download. This is now a commitment
rather than a preference: a sandboxed App Store build places the Unix domain
socket inside the app container, where external agent hooks cannot reach it.

Until an Apple Developer ID exists, releases ship ad-hoc signed instead:
built and published from a v-prefixed git tag by `.github/workflows/release.yml`,
attached to a GitHub release as a universal app zip plus an adapter tarball.
An ad-hoc signature is enough to run on Apple Silicon but not enough for
Gatekeeper, so the notarization gap is handed to the reader as one explicit
one-time quarantine step on the release page and in `docs/install.md` rather
than left to look like a broken download. Signing and notarizing is then a
change to the packaging step alone — the artifacts, the tag trigger, and the
install path do not move.

Agent adapters may be installed separately. If an adapter or CLI is present
while the macOS app is absent or not running, it must fail open: return no
Selection Context, avoid modifying the prompt, and expose diagnostics only on
explicit request.

## Success criteria for the first integration release

- The same selected Source reaches Codex, Claude Code, and Antigravity.
- A prompt submitted with no Selection is byte-for-byte unchanged at the
  adapter's prompt boundary.
- Next Prompt content is injected at most once and cannot leak into a later
  prompt.
- Selections in several Documents under one Working Root all arrive; a
  Selection outside it never does.
- Contexture remains a complete editor when no agent tooling is installed.
- Adapter latency is small enough that prompt submission does not feel delayed.

## Open product questions

- When a Selection crosses blocks, should Contexture offer an explicit
  expansion to the containing heading section?
- What is the retention policy for adapter diagnostics?
- Which standalone Document format follows Markdown, and does it arrive before
  or after the first public release?
- Does the CodeMirror editing surface hold up under a week of real writing, or
  does the loss of macOS text replacement force a native editor pane?
