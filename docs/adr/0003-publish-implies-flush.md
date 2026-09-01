---
status: accepted
date: 2026-09-01
---

# Publishing a Selection Snapshot flushes the Document to disk

Publishing a Selection Snapshot writes the Document's buffer to disk first, so
a snapshot's revision hash is always a hash of what is actually on disk. Agent
Hosts read files from the filesystem and cannot see an editor's in-memory
buffer, so without this the agent would routinely read surrounding context that
disagrees with what the writer is looking at.

The revision hash then does double duty as a conflict detector: when the hash
on disk no longer matches a snapshot's revision, the world has moved and
Contexture can say so instead of guessing.

## Consequences

A Document with no path cannot publish. This is consistent with path being a
separate grant, and it means an untitled scratch buffer is silently
unshareable — the UI must show that rather than appear Armed.

Contexture is **not** the authority over the live Document. Agent Hosts write
files with their own tools, and the filesystem is where those writes land.
Contexture watches the file: when the buffer is clean it reloads, and when the
buffer is dirty it raises a conflict for the writer to resolve. Because
publishing flushes, the buffer is clean at the moment of sharing, so the dirty
case requires the writer to have typed after Arming and before the agent wrote.

Reviewable edit proposals remain desirable but are not part of this decision.
They would require Contexture to mediate writes it currently does not see.
