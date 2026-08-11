#!/usr/bin/env bash
set -euo pipefail

# Build FlutterBuilds.app cleanly from source files in this repository.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/build"
APP_BUNDLE="$BUILD_DIR/FlutterBuilds.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"

echo "=== Building FlutterBuilds.app ==="

# 1. Clean previous build artifact
rm -rf "$APP_BUNDLE"
mkdir -p "$BUILD_DIR"

# 2. Compile AppleScript UI into app bundle
echo "Compiling src/main.applescript..."
osacompile -o "$APP_BUNDLE" "$REPO_ROOT/src/main.applescript"

# 3. Copy mount.sh into Resources and make executable
echo "Installing src/mount.sh..."
cp "$REPO_ROOT/src/mount.sh" "$RESOURCES_DIR/mount.sh"
chmod +x "$RESOURCES_DIR/mount.sh"

# 4. Generate applet.icns from 1024x1024 master PNG
echo "Generating applet.icns..."
"$REPO_ROOT/scripts/make-icns.sh" "$REPO_ROOT/assets/app_icon_1024.png" "$RESOURCES_DIR/applet.icns"

# 5. Patch Info.plist & remove unwanted asset catalogs
echo "Patching Info.plist..."
plutil -replace CFBundleIdentifier -string "local.flutterbuilds" "$INFO_PLIST"
plutil -replace CFBundleIconFile -string "applet" "$INFO_PLIST"
plutil -remove CFBundleIconName "$INFO_PLIST" 2>/dev/null || true

# Remove Assets.car if osacompile created one, to avoid icon catalog precedence issues
rm -f "$RESOURCES_DIR/Assets.car"

# Prevent custom icon detritus
rm -f "$APP_BUNDLE/Icon"$'\r'

# 6. Strip extended attributes & ad-hoc sign the bundle
echo "Signing app bundle..."
xattr -cr "$APP_BUNDLE"
codesign --force --deep --sign - "$APP_BUNDLE"

echo "Build complete: $APP_BUNDLE"
