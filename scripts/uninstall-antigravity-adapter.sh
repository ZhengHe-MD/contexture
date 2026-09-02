#!/usr/bin/env bash
# Reverses scripts/install-antigravity-adapter.sh exactly: removes the
# installed binary and the plugin bundle it wrote, and nothing else. Safe
# to run even if install was never run (every removal is conditional).
set -euo pipefail

INSTALL_DIR="${CONTEXTURE_ANTIGRAVITY_BIN_DIR:-$HOME/Library/Application Support/Contexture/bin}"
PLUGIN_ROOT="${CONTEXTURE_ANTIGRAVITY_PLUGIN_ROOT:-$HOME/.antigravity/plugins/contexture-adapter}"
BIN_PATH="$INSTALL_DIR/antigravity-adapter"

if [ -f "$BIN_PATH" ]; then
  rm -f "$BIN_PATH"
  echo "Removed $BIN_PATH"
else
  echo "No installed binary at $BIN_PATH (already uninstalled?)"
fi

if [ -d "$PLUGIN_ROOT" ]; then
  rm -rf "$PLUGIN_ROOT"
  echo "Removed plugin bundle at $PLUGIN_ROOT"
else
  echo "No plugin bundle at $PLUGIN_ROOT (already uninstalled?)"
fi

# Clean up INSTALL_DIR only if install-antigravity-adapter.sh was the only
# thing ever populating it and it's now empty — never touch it if the
# Claude Code adapter (or anything else) still lives there.
if [ -d "$INSTALL_DIR" ] && [ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
  rmdir "$INSTALL_DIR"
fi
