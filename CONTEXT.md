# Contexture

Contexture is a writing context centered on selecting source text and making
that selection available to an external AI agent without owning the agent
conversation.

## Language

**Document**:
A local text file open in Contexture whose source syntax has a rendered
representation.
_Avoid_: Note, page, Markdown file

**Source**:
The exact bytes of a Document as written by the writer.
_Avoid_: Raw text, input

**Preview**:
The rendered representation of a Document's Source.
_Avoid_: Output, render, WYSIWYG

**Selection**:
The non-empty Source range currently selected by the writer in a Document. A
Selection is always a Source range, whichever pane the writer acted in.
_Avoid_: Highlight, snippet

**Selection Snapshot**:
An immutable, revision-bound record of a Selection that may be shared with an
agent prompt. At most one is Armed per Document.
_Avoid_: Clipboard, selection cache

**Armed**:
The state of a Selection Snapshot that is available for Consumption. Arming
outlives the visible Selection that produced it.
_Avoid_: Active, pending, shared

**Selection Bridge**:
The local boundary through which Contexture publishes Selection Snapshots and
an Agent Adapter reads them.
_Avoid_: Chat server, context database

**Working Root**:
The directory an Agent Host is operating in. It bounds which Selection
Snapshots an Agent Adapter may receive.
_Avoid_: Workspace, project, repo

**Agent Host**:
The application or CLI in which the writer continues an AI conversation.
_Avoid_: Provider, model

**Agent Adapter**:
The agent-specific integration that reads the Selection Bridge and translates
Selection Snapshots into the Agent Host's supported context mechanism.
_Avoid_: Agent, connector

**Selection Context**:
The model-visible, quoted Source data produced from one or more Selection
Snapshots.
_Avoid_: Prompt, instruction

**Sharing Mode**:
The writer-controlled lifetime of Selection Context: Off, Next Prompt, or
Pinned.
_Avoid_: Sync mode, agent mode

**Consumption**:
The successful addition of Selection Context to an Agent Host turn.
_Avoid_: Detection, send
