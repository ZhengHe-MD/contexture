#!/usr/bin/env bash
# Prints the GitHub release body for one version to stdout.
#
# The Gatekeeper step is spelled out inline rather than only linked: with no
# Apple Developer ID behind the build, it is the difference between the
# download working and appearing broken, and a release page is where someone
# is standing when they hit it.
#
# Usage: scripts/release-notes.sh <version> [previous-tag]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release-notes.sh <version> [previous-tag]}"
PREVIOUS="${2:-}"
REPO_URL="https://github.com/ZhengHe-MD/contexture"

cat <<MARKDOWN
Contexture is a macOS editor that shares the exact text you select with the
AI agent you already use. Select in Contexture, switch to your agent, submit
a prompt — the selection joins that prompt's context. Select nothing and
nothing is added.

## Install

Download \`Contexture-$VERSION-macos-universal.zip\`, unzip it, and move
Contexture to \`/Applications\`. Universal (Apple Silicon and Intel), macOS
14 or later.

### One extra step, because this build is not notarized

This project has no Apple Developer ID, so the app is **ad-hoc signed rather
than Developer ID-signed and notarized**. macOS will refuse to open it until
you clear the quarantine flag your browser attached to the download. Run:

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/Contexture.app
\`\`\`

Or do it through the UI: open the app, let the warning appear, then go to
**System Settings → Privacy & Security** and click **Open Anyway** (on macOS
14, Control-click the app in Finder and choose **Open** instead).

Once, per install. Prefer not to? [Build it from source]($REPO_URL/blob/v$VERSION/docs/install.md) — same app.

## Agent Adapters (optional)

Contexture is a complete editor with no adapter installed. To let an agent
read your selections, unpack
\`contexture-adapters-$VERSION-macos-universal.tar.gz\` and run the script
for your Agent Host — the binaries are prebuilt, so no Swift toolchain is
needed:

\`\`\`bash
tar -xzf contexture-adapters-$VERSION-macos-universal.tar.gz
cd contexture-adapters-$VERSION
./scripts/install-claude-code-adapter.sh   # or -codex-, or -antigravity-
\`\`\`

Requires \`jq\`. Every install script has a matching \`uninstall-\` script
that removes exactly what it added.

## Verify your download

\`\`\`bash
shasum -a 256 -c SHA256SUMS.txt
\`\`\`

MARKDOWN

if [ -n "$PREVIOUS" ]; then
  printf '## Changes\n\n'
  git log --pretty='- %s' "$PREVIOUS..HEAD" | grep -v '^- Merge pull request' || true
  printf '\n**Full changelog**: %s/compare/%s...v%s\n' "$REPO_URL" "$PREVIOUS" "$VERSION"
fi

printf '\nFull install and uninstall notes: [docs/install.md](%s/blob/v%s/docs/install.md)\n' \
  "$REPO_URL" "$VERSION"
