# Contexture

Contexture is a macOS-first editor that lets writers share the exact text they
select with the AI agent they already use. The editor stays focused on writing:
conversations remain in Codex, Claude Code, Antigravity, or another compatible
agent host.

Markdown is the first supported format, and the design stays open to other
formats that have a rendered representation.

## Install

Download the latest build from
[Releases](https://github.com/ZhengHe-MD/contexture/releases), or build it
yourself with `./scripts/build-app.sh release`.

The published build is ad-hoc signed rather than Developer ID-signed and
notarized, so macOS blocks it until you clear the download's quarantine flag
once — `xattr -dr com.apple.quarantine /Applications/Contexture.app`.
[docs/install.md](docs/install.md) covers that, the optional Agent Adapters,
and uninstalling.

## Product promise

Select text in Contexture, switch to a compatible agent, and submit a prompt.
The selected text is added to that prompt's model context. If nothing is
selected, Contexture adds nothing.

## Project documents

- [Install guide](docs/install.md)
- [Product definition](docs/product.md)
- [Domain language](CONTEXT.md)
- [Selection Bridge architecture](docs/architecture/selection-bridge.md)
- [Agent compatibility research](docs/research/agent-compatibility.md)
- [Architectural decisions](docs/adr/)
