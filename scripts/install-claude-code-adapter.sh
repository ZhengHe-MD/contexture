#!/usr/bin/env bash
# Minimal, functional install of the Claude Code adapter: builds it, copies
# the binary to a stable path (so it survives .build/ getting cleaned), and
# registers it as a UserPromptSubmit hook in ~/.claude/settings.json.
#
# This is deliberately bare — no per-host status, no diagnostics, no
# uninstall verification. Issue #12 ("Install diagnostics and clean
# uninstall path") is where that belongs; this script exists so issue #3's
# "switch to Claude Code, submit a prompt" promise is something a real user
# can actually reach in the meantime.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

swift build -c release --product ClaudeCodeAdapter

INSTALL_DIR="$HOME/Library/Application Support/Contexture/bin"
mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/claude-code-adapter"
cp "$(swift build -c release --show-bin-path)/ClaudeCodeAdapter" "$BIN_PATH"
chmod +x "$BIN_PATH"

SETTINGS_DIR="$HOME/.claude"
SETTINGS_PATH="$SETTINGS_DIR/settings.json"
mkdir -p "$SETTINGS_DIR"
if [ ! -f "$SETTINGS_PATH" ]; then
  echo '{}' > "$SETTINGS_PATH"
fi

TMP=$(mktemp)
jq --arg cmd "$BIN_PATH" '
  .hooks //= {} |
  .hooks.UserPromptSubmit //= [] |
  .hooks.UserPromptSubmit |= (
    map(select(.hooks[]?.command != $cmd)) + [{"hooks": [{"type": "command", "command": $cmd}]}]
  )
' "$SETTINGS_PATH" > "$TMP"
mv "$TMP" "$SETTINGS_PATH"

echo "Installed $BIN_PATH"
echo "Registered as a UserPromptSubmit hook in $SETTINGS_PATH"
