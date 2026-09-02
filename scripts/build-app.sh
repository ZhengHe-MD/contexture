#!/usr/bin/env bash
# Assembles a local Contexture.app bundle from the SwiftPM build output.
# Not signed or notarized — see docs/product.md "Distribution direction" for
# the eventual Developer ID-signed release path.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build --configuration "$CONFIG"

BUILD_DIR=".build/arm64-apple-macosx/$CONFIG"
if [ ! -d "$BUILD_DIR" ]; then
  BUILD_DIR=$(swift build --configuration "$CONFIG" --show-bin-path)
fi

APP=".build/Contexture.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BUILD_DIR/ContextureApp" "$APP/Contents/MacOS/Contexture"
cp "AppPackaging/Info.plist" "$APP/Contents/Info.plist"
cp "AppPackaging/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

RESOURCE_BUNDLE="$BUILD_DIR/Contexture_ContextureApp.bundle"
if [ -d "$RESOURCE_BUNDLE" ]; then
  cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
fi

echo "Built $APP"
