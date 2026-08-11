#!/usr/bin/env bash
set -euo pipefail

# Generates macOS .icns file with all 10 required representations from a master 1024x1024 PNG.

MASTER_PNG="${1:-assets/app_icon_1024.png}"
OUTPUT_ICNS="${2:-build/applet.icns}"

if [[ ! -f "$MASTER_PNG" ]]; then
  echo "Error: Master icon PNG not found at $MASTER_PNG" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_ICNS")"
ICONSET_DIR="$(mktemp -d)/applet.iconset"
mkdir -p "$ICONSET_DIR"

trap 'rm -rf "$(dirname "$ICONSET_DIR")"' EXIT

# Generate all 10 icon representations required by macOS
sips -z 16 16     "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32     "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32     "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64     "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128   "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256   "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256   "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512   "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512   "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_ICNS"
echo "Generated ICNS at $OUTPUT_ICNS"
