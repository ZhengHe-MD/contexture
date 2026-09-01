---
status: accepted
date: 2026-09-01
---

# Use CodeMirror 6 in a web view rather than a native text view

Contexture's editor and Preview are both CodeMirror 6 and rendered HTML inside
a single `WKWebView`, hosted in a native macOS shell that keeps standard window
chrome, the toolbar, and document plumbing. The deciding requirement is
bidirectional Selection synchronisation: the writer selects in either pane and
sees the Selection in both, which needs one coordinate space and one
position-mapping API. A native `NSTextView` paired with a separate Preview web
view would put a marshalling layer on every selection change and every reflow.

## Considered options

- **`NSTextView` (TextKit 2) with a `WKWebView` Preview** gives full macOS text
  services and the most native writing feel, at the cost of a cross-boundary
  Selection mapping layer maintained by hand, and one syntax highlighter
  written per format.
- **Native Preview via `AttributedString(markdown:)`** would avoid a web view
  entirely, but it does not render GFM tables, fenced code blocks, or inline
  images, and it is a dead end the moment HTML becomes a supported format.

## Consequences

macOS autocorrect and text replacement degrade inside a web view. Spellcheck
and dictation still work, and those are the two writers notice most.
Accessibility is CodeMirror's ARIA rather than native `NSAccessibility`. The
split divider is CSS inside the web view rather than an `NSSplitView`, which
satisfies the continuous full-height requirement visually but is not literally
native.

The Preview web view runs with JavaScript disabled and remote loads blocked.
This is not optional: GFM permits raw HTML inside a Document, so a Document
containing a remote image would otherwise turn the Preview into a beacon
reporting when the writer opened the file.

This decision should be revisited after a week of real writing. If the missing
text replacement is a daily irritation, the editor pane moves to `NSTextView`
and the Selection mapping layer becomes the accepted cost.
