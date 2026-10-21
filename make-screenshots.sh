#!/bin/bash
# Regenerates the README images: captures the app's windows, then composes them onto a backdrop.
set -euo pipefail
cd "$(dirname "$0")"
SAMPLE="${1:?usage: make-screenshots.sh <sample image>}"
BUILD="$PWD/build"
mkdir -p "$BUILD/shots" docs
rm -f "$BUILD/shots"/*.png
( /Applications/Clementine.app/Contents/MacOS/Clementine --screenshots "$SAMPLE" "$BUILD/shots" & PID=$!; sleep 25; kill $PID 2>/dev/null || true; wait $PID 2>/dev/null || true )
swiftc_() { swiftc -vfsoverlay "$BUILD/overlay.yaml" -module-cache-path "$BUILD/mc" -swift-version 5 -O "$@"; }
swiftc_ Assets/Compose.swift -o "$BUILD/compose" 2>&1 | grep -E "error" || true
"$BUILD/compose" "$BUILD/shots" docs
sips -s format png "$BUILD/AppIcon.iconset/icon_256x256.png" --out docs/icon.png >/dev/null
