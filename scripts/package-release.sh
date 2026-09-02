#!/usr/bin/env bash
# Produces every artifact attached to a GitHub release, into dist/.
#
#   dist/Contexture-<version>-macos-universal.zip
#       The app bundle, ad-hoc signed. Not notarized — docs/install.md
#       carries the Gatekeeper step users have to run once.
#   dist/contexture-adapters-<version>-macos-universal.tar.gz
#       The three Agent Adapter binaries plus their install/uninstall
#       scripts, self-contained: no Swift toolchain and no checkout needed.
#   dist/SHA256SUMS.txt
#
# Usage: scripts/package-release.sh <version>
# Environment:
#   CONTEXTURE_BUILD=17   CFBundleVersion to stamp (default: 1)
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=lib/universal-build.sh
. "$SCRIPT_DIR/lib/universal-build.sh"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
  echo "usage: scripts/package-release.sh <version>" >&2
  exit 1
fi

ADAPTERS=(ClaudeCodeAdapter CodexAdapter AntigravityAdapter)
DIST="dist"
rm -rf "$DIST"
mkdir -p "$DIST"

# --- The app ------------------------------------------------------------
# build-app.sh builds every product in the package, so the adapter binaries
# staged below come out of the same compilation as the app the user runs.
CONTEXTURE_UNIVERSAL=1 \
CONTEXTURE_VERSION="$VERSION" \
CONTEXTURE_BUILD="${CONTEXTURE_BUILD:-1}" \
  "$SCRIPT_DIR/build-app.sh" release

APP_ZIP="$DIST/Contexture-$VERSION-macos-universal.zip"
# ditto, not zip(1): it preserves the bundle's symlinks and resource forks,
# so the signature still verifies after a round trip.
ditto -c -k --sequesterRsrc --keepParent .build/Contexture.app "$APP_ZIP"

# --- The adapters -------------------------------------------------------
contexture_build release arm64 x86_64

STAGE_ROOT="$(mktemp -d)"
trap 'rm -rf "$STAGE_ROOT"' EXIT
STAGE_NAME="contexture-adapters-$VERSION"
STAGE="$STAGE_ROOT/$STAGE_NAME"
mkdir -p "$STAGE/bin" "$STAGE/scripts/lib"

for product in "${ADAPTERS[@]}"; do
  contexture_fuse "$product" "$STAGE/bin/$product" "${CONTEXTURE_BIN_DIRS[@]}"
  codesign --force --sign - "$STAGE/bin/$product"
done

# The install scripts find bin/ next to scripts/ and skip the build path
# entirely — see scripts/lib/adapter-binary.sh.
cp scripts/install-*-adapter.sh scripts/uninstall-*-adapter.sh "$STAGE/scripts/"
cp scripts/lib/adapter-binary.sh "$STAGE/scripts/lib/"
cp docs/install.md "$STAGE/README.md"

tar -czf "$DIST/contexture-adapters-$VERSION-macos-universal.tar.gz" \
  -C "$STAGE_ROOT" "$STAGE_NAME"

# --- Checksums ----------------------------------------------------------
(cd "$DIST" && shasum -a 256 ./*.zip ./*.tar.gz > SHA256SUMS.txt)

echo
echo "Artifacts in $DIST:"
ls -lh "$DIST"
