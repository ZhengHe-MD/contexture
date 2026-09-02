#!/usr/bin/env bash
# Runs install-then-uninstall for all three Adapters against scratch
# paths and confirms nothing is left behind — the "Uninstall is verified
# for all three adapters" / "leaving no residue" acceptance criteria for
# issue #12, as a repeatable script rather than the one-off manual check
# that originally verified them.
#
# Entirely scratch-scoped: every config/plugin path is overridden via each
# script's own env var (CLAUDE_CODE_SETTINGS_PATH, CODEX_CONFIG_PATH,
# CONTEXTURE_ANTIGRAVITY_BIN_DIR/PLUGIN_ROOT). The one exception is the
# shared binary install directory ($HOME/Library/Application Support/
# Contexture/bin) — Claude Code's and Codex's scripts have no override for
# it, so this does briefly create real files there; uninstall removes them
# and this script confirms the directory is gone again afterward.
set -euo pipefail
cd "$(dirname "$0")/.."

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

export CLAUDE_CODE_SETTINGS_PATH="$SCRATCH/claude-settings.json"
export CODEX_CONFIG_PATH="$SCRATCH/codex-config.json"
export CONTEXTURE_ANTIGRAVITY_BIN_DIR="$SCRATCH/antigravity-bin"
export CONTEXTURE_ANTIGRAVITY_PLUGIN_ROOT="$SCRATCH/antigravity-plugin"

INSTALL_DIR="$HOME/Library/Application Support/Contexture/bin"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

echo "== Installing all three =="
./scripts/install-claude-code-adapter.sh
./scripts/install-codex-adapter.sh
./scripts/install-antigravity-adapter.sh

[ -f "$INSTALL_DIR/claude-code-adapter" ] || fail "claude-code-adapter binary missing after install"
[ -f "$INSTALL_DIR/codex-adapter" ] || fail "codex-adapter binary missing after install"
[ -f "$CONTEXTURE_ANTIGRAVITY_BIN_DIR/antigravity-adapter" ] || fail "antigravity-adapter binary missing after install"
grep -q "claude-code-adapter" "$CLAUDE_CODE_SETTINGS_PATH" || fail "Claude Code hook not registered"
grep -q "codex-adapter" "$CODEX_CONFIG_PATH" || fail "Codex hook not registered"
[ -f "$CONTEXTURE_ANTIGRAVITY_PLUGIN_ROOT/hooks.json" ] || fail "Antigravity plugin bundle missing after install"

echo "== Uninstalling all three =="
./scripts/uninstall-claude-code-adapter.sh
./scripts/uninstall-codex-adapter.sh
./scripts/uninstall-antigravity-adapter.sh

[ ! -f "$INSTALL_DIR/claude-code-adapter" ] || fail "claude-code-adapter binary still present after uninstall"
[ ! -f "$INSTALL_DIR/codex-adapter" ] || fail "codex-adapter binary still present after uninstall"
[ ! -d "$INSTALL_DIR" ] || fail "shared install directory still present after uninstall (should be removed once empty)"
[ ! -f "$CONTEXTURE_ANTIGRAVITY_BIN_DIR/antigravity-adapter" ] || fail "antigravity-adapter binary still present after uninstall"
[ ! -d "$CONTEXTURE_ANTIGRAVITY_PLUGIN_ROOT" ] || fail "Antigravity plugin bundle still present after uninstall"
if command -v jq >/dev/null 2>&1; then
  claude_still_registered=$(jq '(.hooks.UserPromptSubmit // []) | any(.hooks[]?.command | test("claude-code-adapter"))' "$CLAUDE_CODE_SETTINGS_PATH")
  [ "$claude_still_registered" = "false" ] || fail "Claude Code hook entry still present after uninstall"
  codex_still_registered=$(jq '(.hooks.UserPromptSubmit // []) | any(.hooks[]?.command | test("codex-adapter"))' "$CODEX_CONFIG_PATH")
  [ "$codex_still_registered" = "false" ] || fail "Codex hook entry still present after uninstall"
fi

echo "OK: all three adapters install and uninstall cleanly, with no residue."
