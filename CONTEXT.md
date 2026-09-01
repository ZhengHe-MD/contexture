# Contexture

Contexture is a Markdown writing context centered on selecting source text and
making that selection available to an external AI agent without owning the
agent conversation.

## Language

**Document**:
A local Markdown file open in Contexture.
_Avoid_: Note, page

**Selection**:
The non-empty source range currently selected by the writer in a Document.
_Avoid_: Highlight, snippet

**Selection Snapshot**:
An immutable, revision-bound record of a Selection that may be shared with one
agent prompt.
_Avoid_: Clipboard, selection cache

**Selection Bridge**:
The local boundary through which Contexture publishes a Selection Snapshot and
an Agent Adapter reads it.
_Avoid_: Chat server, context database

**Agent Host**:
The application or CLI in which the writer continues an AI conversation.
_Avoid_: Provider, model

**Agent Adapter**:
The agent-specific integration that reads the Selection Bridge and translates
a Selection Snapshot into the Agent Host's supported context mechanism.
_Avoid_: Agent, connector

**Selection Context**:
The model-visible, quoted Markdown data produced from a Selection Snapshot.
_Avoid_: Prompt, instruction

**Sharing Mode**:
The writer-controlled lifetime of Selection Context: Off, Next Prompt, or
Pinned.
_Avoid_: Sync mode, agent mode

**Consumption**:
The successful addition of Selection Context to an Agent Host turn.
_Avoid_: Detection, send

