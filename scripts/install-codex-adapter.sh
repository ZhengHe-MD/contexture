#!/usr/bin/env bash
# Minimal, functional install of the Codex adapter: builds it, copies the
# binary to a stable path (so it survives .build/ getting cleaned), and
# registers it as a UserPromptSubmit hook in Codex's config file.
#
# UNVERIFIED ASSUMPTION, read before relying on this script:
# docs/research/agent-compatibility.md (this project's authoritative source
# for Codex's *hook contract*: the UserPromptSubmit event, the pending
# prompt, the turn ID, hookSpecificOutput.additionalContext) says nothing
# about *where Codex's config file lives or what format it's in* — only
# that hooks "can be installed globally, per repository, or through a
# plugin." Lacking a concrete primary source for that, this script guesses:
#   - Location: "$HOME/.codex/config.json" — the same "~/.<cli-name>/<file>"
#     shape as Claude Code's real "$HOME/.claude/settings.json".
#   - Format and hook registration shape: JSON, mirroring Claude Code's own
#     settings.json hooks.UserPromptSubmit array structure — justified only
#     by the research doc's separate note that Codex's hook *shape* (event
#     name, additionalContext field) is close to Claude Code's. That
#     resemblance is about the hook payload, not necessarily the host's
#     on-disk config format, so treat this as a best-effort placeholder, not
#     a confirmed fact.
# If Codex actually uses e.g. a TOML config (as OpenAI's real-world Codex
# CLI does for its general settings) or a different path, override the
# location with CODEX_CONFIG_PATH and adjust the jq block below accordingly
# — the binary build/copy steps above are unaffected either way.
#
# This is deliberately bare — no per-host status, no diagnostics — the same
# scope Claude Code's install script chose (see its own header comment,
# which points at issue #12 for that follow-up work).
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

swift build -c release --product CodexAdapter

INSTALL_DIR="$HOME/Library/Application Support/Contexture/bin"
mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/codex-adapter"
cp "$(swift build -c release --show-bin-path)/CodexAdapter" "$BIN_PATH"
chmod +x "$BIN_PATH"

CONFIG_PATH="${CODEX_CONFIG_PATH:-$HOME/.codex/config.json}"
CONFIG_DIR="$(dirname "$CONFIG_PATH")"
mkdir -p "$CONFIG_DIR"
if [ ! -f "$CONFIG_PATH" ]; then
  echo '{}' > "$CONFIG_PATH"
fi

TMP=$(mktemp)
jq --arg cmd "$BIN_PATH" '
  .hooks //= {} |
  .hooks.UserPromptSubmit //= [] |
  .hooks.UserPromptSubmit |= (
    map(select(.hooks[]?.command != $cmd)) + [{"hooks": [{"type": "command", "command": $cmd}]}]
  )
' "$CONFIG_PATH" > "$TMP"
mv "$TMP" "$CONFIG_PATH"

echo "Installed $BIN_PATH"
echo "Registered as a UserPromptSubmit hook in $CONFIG_PATH"
echo "NOTE: $CONFIG_PATH's location and JSON shape are a best-effort guess," \
     "not a confirmed Codex config format — see this script's header comment."
