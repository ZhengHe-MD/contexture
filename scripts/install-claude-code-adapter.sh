#!/usr/bin/env bash
# Minimal, functional install of the Claude Code adapter: puts a binary at a
# stable path (so it survives .build/ getting cleaned) and registers it as a
# UserPromptSubmit hook in ~/.claude/settings.json.
#
# The binary comes from a source build here, or from the prebuilt bin/ in a
# release tarball — see scripts/lib/adapter-binary.sh.
#
# See scripts/uninstall-claude-code-adapter.sh for the reverse, and
# scripts/verify-adapter-install.sh (issue #12) for the install+uninstall
# residue check exercised against a scratch settings file via
# CLAUDE_CODE_SETTINGS_PATH below — never the real one.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=lib/adapter-binary.sh
. "$SCRIPT_DIR/lib/adapter-binary.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

# Overridable for testing against a scratch file instead of the real
# machine — real installations should leave this unset.
SETTINGS_PATH="${CLAUDE_CODE_SETTINGS_PATH:-$HOME/.claude/settings.json}"

INSTALL_DIR="$HOME/Library/Application Support/Contexture/bin"
mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/claude-code-adapter"
cp "$(resolve_adapter_binary ClaudeCodeAdapter)" "$BIN_PATH"
chmod +x "$BIN_PATH"

SETTINGS_DIR="$(dirname "$SETTINGS_PATH")"
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
