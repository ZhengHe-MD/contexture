#!/usr/bin/env bash
# Reverses install-codex-adapter.sh: removes the registered UserPromptSubmit
# hook entry from Codex's config file and deletes the installed binary.
# Idempotent — safe to run whether or not the adapter is currently
# installed, and leaves the rest of the config file untouched.
#
# Same UNVERIFIED ASSUMPTION as install-codex-adapter.sh: Codex's real
# config file location/format has no confirmed primary source in
# docs/research/agent-compatibility.md. This targets the same best-effort
# "$HOME/.codex/config.json" (JSON, Claude-Code-shaped hooks array) unless
# overridden with CODEX_CONFIG_PATH — see that script's header comment for
# the full reasoning.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required (brew install jq)" >&2
  exit 1
fi

INSTALL_DIR="$HOME/Library/Application Support/Contexture/bin"
BIN_PATH="$INSTALL_DIR/codex-adapter"
CONFIG_PATH="${CODEX_CONFIG_PATH:-$HOME/.codex/config.json}"

if [ -f "$CONFIG_PATH" ]; then
  TMP=$(mktemp)
  # `.hooks.UserPromptSubmit // []` (not `// empty`) is deliberate: indexing
  # a missing `.hooks` is `null`, and `null // empty` produces *zero* jq
  # output rather than `null` — piped into `mv`, that would silently
  # truncate the whole config file to empty. `// []` always yields exactly
  # one value, so this is a no-op edit whenever there is nothing to remove.
  jq --arg cmd "$BIN_PATH" '
    if ((.hooks.UserPromptSubmit // []) | any(.hooks[]?.command == $cmd)) then
      .hooks.UserPromptSubmit |= map(select(.hooks[]?.command != $cmd))
    else
      .
    end
  ' "$CONFIG_PATH" > "$TMP"
  mv "$TMP" "$CONFIG_PATH"
  echo "Removed the UserPromptSubmit hook entry (if any) from $CONFIG_PATH"
else
  echo "No config file at $CONFIG_PATH; nothing to unregister"
fi

if [ -f "$BIN_PATH" ]; then
  rm -f "$BIN_PATH"
  echo "Removed $BIN_PATH"
else
  echo "No installed binary at $BIN_PATH; nothing to remove"
fi
