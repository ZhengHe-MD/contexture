---
status: accepted
date: 2026-09-01
---

# Return multiple Selection Snapshots, scoped to the Working Root

`read` returns every Armed Selection Snapshot whose Document lies under the
requesting Agent Host's Working Root, ordered most-recently-selected first,
rather than a single active snapshot. A writer working across several files
wants the agent aware of the selections in all of them.

This reverses the earlier boundary that the Selection Bridge must never expose
an inventory of open Documents. The reversal is safe only because of the
scoping: a Document under the Working Root is one the Agent Host can already
read, so disclosing it reveals nothing the agent could not obtain on its own.
Documents outside the Working Root are not returned at all.

## Considered options

- **One active snapshot, most-recent wins** is simpler and preserves the
  original boundary exactly, but with Arming that survives Selection collapse
  it discards selections the writer deliberately made in other files.
- **All open Documents, including those with no Selection** was rejected
  outright: it would ship whole Document contents and destroy the
  selection-only disclosure boundary.

## Consequences

The response carries several delimited blocks, so the Adapter needs a
per-snapshot cap and a **total** cap, with visible truncation before a snapshot
becomes shareable. Most-recently-selected ordering means truncation drops the
least relevant Selection rather than an arbitrary one.

Paths are disclosed relative to the Working Root, and only for Documents inside
it. The invariant is that Contexture never reveals a location the Agent Host
could not already reach. Absolute paths never leave the Selection Bridge; they
are used internally for scope matching only.
