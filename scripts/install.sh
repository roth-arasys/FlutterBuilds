#!/usr/bin/env bash
set -euo pipefail

# Install FlutterBuilds.app to ~/Applications and register login item.
# Does NOT touch ~/Library/Application Support/FlutterBuilds/ where runtime data lives.

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_APP="$REPO_ROOT/build/FlutterBuilds.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/FlutterBuilds.app"

if [[ ! -d "$BUILD_APP" ]]; then
  echo "Error: $BUILD_APP does not exist. Run 'make build' first." >&2
  exit 1
fi

echo "=== Installing FlutterBuilds.app ==="
mkdir -p "$DEST_DIR"

# Copy app bundle to ~/Applications
rm -rf "$DEST_APP"
cp -R "$BUILD_APP" "$DEST_APP"

# Ensure clean xattrs and ad-hoc signature after copy
xattr -cr "$DEST_APP"
codesign --force --deep --sign - "$DEST_APP"

# Reregister with LaunchServices
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  echo "Registering application with LaunchServices..."
  "$LSREGISTER" -f "$DEST_APP"
fi

# Add to Login Items if not already present
echo "Registering Login Item..."
osascript -e "
tell application \"System Events\"
  if not (exists login item \"FlutterBuilds\") then
    make new login item at end with properties {path:\"$DEST_APP\", hidden:true}
  end if
end tell
" || echo "Warning: Could not set login item (requires Automation consent for System Events)."

echo "Installed successfully to $DEST_APP"
