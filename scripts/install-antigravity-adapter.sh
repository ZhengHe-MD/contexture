#!/usr/bin/env bash
# Installs the Antigravity 2.x desktop adapter as a global plugin bundle:
# builds it, copies the binary to a stable path, and writes Antigravity's
# documented root-level plugin.json and hooks.json files. See
# docs/research/agent-compatibility.md for the primary-source links.
#
# Reversible: scripts/uninstall-antigravity-adapter.sh removes exactly what
# this script creates and nothing else.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product AntigravityAdapter

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq is required" >&2
  exit 1
fi

# Overridable for testing against a scratch directory instead of the real
# machine (see this script's own test coverage / issue #11's brief: "do not
# run this against any real config file on this machine"). Real
# installations should leave both unset and get the defaults below.
INSTALL_DIR="${CONTEXTURE_ANTIGRAVITY_BIN_DIR:-$HOME/Library/Application Support/Contexture/bin}"
PLUGIN_ROOT="${CONTEXTURE_ANTIGRAVITY_PLUGIN_ROOT:-$HOME/.gemini/config/plugins/contexture-adapter}"

mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/antigravity-adapter"
cp "$(swift build -c release --show-bin-path)/AntigravityAdapter" "$BIN_PATH"
chmod +x "$BIN_PATH"

mkdir -p "$PLUGIN_ROOT"

jq -n '{"name": "contexture-adapter"}' > "$PLUGIN_ROOT/plugin.json"

HOOK_COMMAND="\"$BIN_PATH\""
jq -n --arg command "$HOOK_COMMAND" '{
  "contexture-selection": {
    "PreInvocation": [
      {
        "type": "command",
        "command": $command,
        "timeout": 5
      }
    ]
  }
}' > "$PLUGIN_ROOT/hooks.json"

echo "Installed $BIN_PATH"
echo "Wrote a plugin bundle at $PLUGIN_ROOT registering it against PreInvocation"
