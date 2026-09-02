#!/usr/bin/env bash
# Assembles a Contexture.app bundle from the SwiftPM build output.
#
# Ad-hoc signed, never Developer ID-signed or notarized: the project has no
# Apple Developer ID (see docs/product.md "Distribution direction"). An
# ad-hoc signature is what lets the binary run at all on Apple Silicon; it
# does not satisfy Gatekeeper, so a *downloaded* build stays quarantined
# until the user clears it by hand. docs/install.md tells them how.
#
# Usage: scripts/build-app.sh [debug|release]
#
# Environment:
#   CONTEXTURE_UNIVERSAL=1     build arm64 + x86_64 and lipo them together
#   CONTEXTURE_VERSION=0.1.0   stamp CFBundleShortVersionString
#   CONTEXTURE_BUILD=17        stamp CFBundleVersion
#   CONTEXTURE_APP_DIR=dir     directory to write Contexture.app into
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=lib/universal-build.sh
. "$SCRIPT_DIR/lib/universal-build.sh"

CONFIG="${1:-debug}"

ARCHS=()
if [ "${CONTEXTURE_UNIVERSAL:-0}" = "1" ]; then
  ARCHS=(arm64 x86_64)
fi

contexture_build "$CONFIG" "${ARCHS[@]+"${ARCHS[@]}"}"

APP="${CONTEXTURE_APP_DIR:-.build}/Contexture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

contexture_fuse ContextureApp "$APP/Contents/MacOS/Contexture" "${CONTEXTURE_BIN_DIRS[@]}"
cp "AppPackaging/Info.plist" "$APP/Contents/Info.plist"
cp "AppPackaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# The resource bundle is architecture-independent, so any one arch's copy
# will do.
RESOURCE_BUNDLE="${CONTEXTURE_BIN_DIRS[0]}/Contexture_ContextureApp.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi

if [ -n "${CONTEXTURE_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c \
    "Set :CFBundleShortVersionString $CONTEXTURE_VERSION" "$APP/Contents/Info.plist"
fi
if [ -n "${CONTEXTURE_BUILD:-}" ]; then
  /usr/libexec/PlistBuddy -c \
    "Set :CFBundleVersion $CONTEXTURE_BUILD" "$APP/Contents/Info.plist"
fi

# Re-seal the bundle after the edits above. `--force` replaces the linker's
# own ad-hoc signature on the executable we just lipo'd and rewrote.
codesign --force --sign - "$APP"

echo "Built $APP"
codesign --display --verbose=2 "$APP" 2>&1 | sed -n 's/^/  /p'
