#!/usr/bin/env bash
# Installs the Antigravity adapter as an Antigravity plugin bundle: builds
# it, copies the binary to a stable path (so it survives .build/ getting
# cleaned — mirrors scripts/install-claude-code-adapter.sh), and writes a
# plugin manifest + hooks file registering it against the `PreInvocation`
# hook.
#
# IMPORTANT — read before running this for real:
#
# Antigravity's actual plugin directory location, discovery mechanism, and
# exact hook-manifest JSON schema are NOT confirmed by any source available
# to this repo. docs/research/agent-compatibility.md's "Google Antigravity"
# section (this repo's authoritative research doc for issue #11) documents
# *behavior* ("PreInvocation runs before each model call, may return
# injectSteps... plugins can bundle hooks and MCP configuration") but never
# a wire or file-format schema, and this task deliberately does not go
# hunting further outside doc for one.
#
# What this script writes is a *structural analog*, not a confirmed
# format: the manifest/hooks split below (a top-level plugin.json pointing
# at a separate hooks.json, itself mapping a hook event name to an array of
# {"hooks": [{"type": "command", "command": ...}]} groups) is modeled
# directly on Claude Code's real, confirmed plugin format
# (.claude-plugin/plugin.json + hooks/hooks.json — see
# scripts/install-claude-code-adapter.sh for the sibling settings.json-style
# registration Claude Code itself actually uses). It is the best available
# analog given both products are documented as supporting "bundled hooks",
# but it is a guess about Antigravity specifically, not a verified fact.
# The plugin root path below (~/.antigravity/plugins/<name>/) is likewise a
# guess, chosen only because it mirrors the ~/.claude/ convention this repo
# can otherwise confirm.
#
# Before trusting this against a real Antigravity installation: check
# Antigravity's own current plugin documentation and adjust the path/shape
# below if it disagrees. Do not treat this script's output as evidence of
# what Antigravity actually expects.
#
# Reversible: scripts/uninstall-antigravity-adapter.sh removes exactly what
# this script creates and nothing else.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product AntigravityAdapter

# Overridable for testing against a scratch directory instead of the real
# machine (see this script's own test coverage / issue #11's brief: "do not
# run this against any real config file on this machine"). Real
# installations should leave both unset and get the defaults below.
INSTALL_DIR="${CONTEXTURE_ANTIGRAVITY_BIN_DIR:-$HOME/Library/Application Support/Contexture/bin}"
PLUGIN_ROOT="${CONTEXTURE_ANTIGRAVITY_PLUGIN_ROOT:-$HOME/.antigravity/plugins/contexture-adapter}"

mkdir -p "$INSTALL_DIR"
BIN_PATH="$INSTALL_DIR/antigravity-adapter"
cp "$(swift build -c release --show-bin-path)/AntigravityAdapter" "$BIN_PATH"
chmod +x "$BIN_PATH"

rm -rf "$PLUGIN_ROOT"
mkdir -p "$PLUGIN_ROOT/.antigravity-plugin" "$PLUGIN_ROOT/hooks"

cat > "$PLUGIN_ROOT/.antigravity-plugin/plugin.json" <<EOF
{
  "name": "contexture-adapter",
  "displayName": "Contexture Selection Bridge Adapter",
  "version": "0.1.0",
  "description": "Injects the current Contexture Selection Context into PreInvocation, at most once per user turn.",
  "hooks": "./hooks/hooks.json"
}
EOF

cat > "$PLUGIN_ROOT/hooks/hooks.json" <<EOF
{
  "hooks": {
    "PreInvocation": [
      {
        "matcher": "*",
        "hooks": [
          {
            "type": "command",
            "command": "$BIN_PATH"
          }
        ]
      }
    ]
  }
}
EOF

echo "Installed $BIN_PATH"
echo "Wrote a plugin bundle at $PLUGIN_ROOT registering it against PreInvocation"
echo
echo "NOTE: the plugin directory location and manifest schema above are an"
echo "unconfirmed best-effort guess (see this script's header comment) —"
echo "verify against Antigravity's real, current plugin documentation before"
echo "relying on this for anything but a starting point."
