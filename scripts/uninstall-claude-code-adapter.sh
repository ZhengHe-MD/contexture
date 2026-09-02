#!/usr/bin/env bash
# Reverses install-claude-code-adapter.sh: removes the registered
# UserPromptSubmit hook entry from Claude Code's settings.json and deletes
# the installed binary. Idempotent — safe to run whether or not the
# adapter is currently installed — and leaves the rest of the settings
# file untouched.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

INSTALL_DIR="$HOME/Library/Application Support/Contexture/bin"
BIN_PATH="$INSTALL_DIR/claude-code-adapter"
SETTINGS_PATH="${CLAUDE_CODE_SETTINGS_PATH:-$HOME/.claude/settings.json}"

if [ -f "$SETTINGS_PATH" ]; then
  TMP=$(mktemp)
  # `.hooks.UserPromptSubmit // []` (not `// empty`) is deliberate: indexing
  # a missing `.hooks` is `null`, and `null // empty` produces *zero* jq
  # output rather than `null` — piped into `mv`, that would silently
  # truncate the whole settings file to empty.
  jq --arg cmd "$BIN_PATH" '
    if ((.hooks.UserPromptSubmit // []) | any(.hooks[]?.command == $cmd)) then
      .hooks.UserPromptSubmit |= map(select(.hooks[]?.command != $cmd))
    else
      .
    end
  ' "$SETTINGS_PATH" > "$TMP"
  mv "$TMP" "$SETTINGS_PATH"
  echo "Removed the UserPromptSubmit hook entry (if any) from $SETTINGS_PATH"
else
  echo "No settings file at $SETTINGS_PATH; nothing to unregister"
fi

if [ -f "$BIN_PATH" ]; then
  rm -f "$BIN_PATH"
  echo "Removed $BIN_PATH"
else
  echo "No installed binary at $BIN_PATH; nothing to remove"
fi

if [ -d "$INSTALL_DIR" ] && [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  rmdir "$INSTALL_DIR"
fi
