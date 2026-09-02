---
status: accepted
date: 2026-09-02
---

# Render Mermaid blocks as inert images

Contexture renders lowercase `mermaid` fenced blocks with an exact, bundled
Mermaid version in the trusted outer editor page, using Mermaid's strict
security level and fixed resource limits. It removes active elements and every
non-fragment resource reference from the generated SVG, encodes that SVG as a
`data:` image, and sends it through the existing native sanitizer and CSP
wrapper before it reaches the script-free Preview iframe. This keeps a Diagram
static and offline while permitting safe author-controlled presentation
configuration.

## Considered options

- Allowing Mermaid to run inside the Preview would weaken ADR-0002's central
  no-script boundary and interfere with Preview-to-Source Selection mapping.
- Rendering through a CLI or service would add a second runtime or a network
  dependency to an otherwise self-contained live Preview.
- Inline generated SVG would preserve selectable labels, but would expand the
  active-content sanitizer's trusted surface. An inert image makes the whole
  Diagram one explicit, source-ranged Preview node instead.

## Consequences

A Preview Selection that touches a Diagram maps to the entire Mermaid Block;
individual Diagram labels are not selectable. Diagrams render concurrently and
the Preview changes only when the complete current render is ready. Invalid or
over-limit Diagram Source becomes an inline error rather than a stale Diagram,
and Mermaid upgrades are deliberate lockfile changes.
