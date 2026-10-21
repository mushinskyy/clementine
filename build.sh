#!/bin/bash
# Builds Clementine.app with the Swift command-line toolchain (no Xcode needed)
# and installs it into /Applications (falls back to ~/Applications).
set -euo pipefail
cd "$(dirname "$0")"

APP=Clementine
BUILD="$PWD/build"
BUNDLE="$BUILD/$APP.app"
rm -rf "$BUILD"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources" "$BUILD/mc" "$BUILD/AppIcon.iconset"

# The Command Line Tools ship a stale module map that clashes with the SDK;
# hide it through a virtual-filesystem overlay instead of touching the system.
: > "$BUILD/empty.modulemap"
cat > "$BUILD/overlay.yaml" <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [
  { "name": "/Library/Developer/CommandLineTools/usr/include/swift", "type": "directory", "contents": [
     { "name": "module.modulemap", "type": "file", "external-contents": "$BUILD/empty.modulemap" } ] } ] }
EOF
swiftc_() { swiftc -vfsoverlay "$BUILD/overlay.yaml" -module-cache-path "$BUILD/mc" -swift-version 5 -O -target arm64-apple-macos13.0 "$@"; }

echo "▸ App icon"
swiftc_ Assets/MakeIcon.swift -o "$BUILD/makeicon" 2>&1 | grep -E "error" || true
"$BUILD/makeicon" "$BUILD/AppIcon.iconset"
iconutil -c icns "$BUILD/AppIcon.iconset" -o "$BUNDLE/Contents/Resources/AppIcon.icns"

echo "▸ Compiling"
swiftc_ Sources/*.swift -o "$BUNDLE/Contents/MacOS/$APP" \
  -framework AppKit -framework SwiftUI -framework AVFoundation -framework PDFKit \
  -framework Vision -framework CoreImage -framework UniformTypeIdentifiers -framework ServiceManagement \
  2>&1 | grep -E "error|warning: unre" || true
test -x "$BUNDLE/Contents/MacOS/$APP"

cp Info.plist "$BUNDLE/Contents/Info.plist"
echo -n "APPL????" > "$BUNDLE/Contents/PkgInfo"

echo "▸ Bundling ffmpeg"
# Static Apple-silicon ffmpeg (GPL build by Martin Riedl), fetched on first build and
# checksum-verified. Set CLEMENTINE_NO_FFMPEG=1 to build without it.
FF_BASE="https://ffmpeg.martin-riedl.de/download/macos/arm64/1789931890_9.0.2"
FF_SHA="c8ed4c4e6978a03c485edbfe4e0a5dc2380f8a30bba5150531b31b094492d924"
FP_SHA="fcbe839537485eaee7a7a8bc5cbc0f90d53617e80943e8a5b2e31cb851197ea6"
if [ ! -x Vendor/ffmpeg/ffmpeg ] && [ -z "${CLEMENTINE_NO_FFMPEG:-}" ]; then
  echo "  downloading ffmpeg 9.0.2 (about 60 MB)…"
  mkdir -p Vendor/ffmpeg Vendor/dl
  curl -sSL -o Vendor/dl/ffmpeg.zip "$FF_BASE/ffmpeg.zip"
  curl -sSL -o Vendor/dl/ffprobe.zip "$FF_BASE/ffprobe.zip"
  echo "$FF_SHA  Vendor/dl/ffmpeg.zip" | shasum -a 256 -c -
  echo "$FP_SHA  Vendor/dl/ffprobe.zip" | shasum -a 256 -c -
  ditto -x -k Vendor/dl/ffmpeg.zip Vendor/ffmpeg
  ditto -x -k Vendor/dl/ffprobe.zip Vendor/ffmpeg
  curl -sSL -o Vendor/ffmpeg/VERSIONS.txt "$FF_BASE/versions.txt" || true
  rm -rf Vendor/dl
fi
if [ -x Vendor/ffmpeg/ffmpeg ]; then
  cp Vendor/ffmpeg/ffmpeg Vendor/ffmpeg/ffprobe "$BUNDLE/Contents/Resources/"
  cp Vendor/ffmpeg/VERSIONS.txt "$BUNDLE/Contents/Resources/ffmpeg-VERSIONS.txt" 2>/dev/null || true
  codesign --force --sign - "$BUNDLE/Contents/Resources/ffmpeg" "$BUNDLE/Contents/Resources/ffprobe"
else
  echo "  (Vendor/ffmpeg/ffmpeg missing; building without ffmpeg)"
fi

echo "▸ Finder extension"
EXT="$BUNDLE/Contents/PlugIns/ClementineFinder.appex"
mkdir -p "$EXT/Contents/MacOS"
swiftc_ -parse-as-library -module-name ClementineFinder -application-extension FinderExt/FinderSync.swift \
  -o "$EXT/Contents/MacOS/ClementineFinder" -framework FinderSync -framework AppKit \
  -Xlinker -e -Xlinker _NSExtensionMain 2>&1 | grep -E "error" || true
test -x "$EXT/Contents/MacOS/ClementineFinder"
cp FinderExt/Info.plist "$EXT/Contents/Info.plist"
codesign --force --sign - --entitlements FinderExt/ext.entitlements "$EXT"
# Identifier-based designated requirement: Accessibility and other privacy grants
# survive rebuilds (an ad-hoc cdhash requirement would change with every build).
codesign --force --sign - --requirements '=designated => identifier "app.clementine.mac"' "$BUNDLE"

echo "▸ Installing"
DEST=/Applications
if [ ! -w "$DEST" ]; then DEST="$HOME/Applications"; mkdir -p "$DEST"; fi
pkill -x "$APP" 2>/dev/null || true
rm -rf "$DEST/$APP.app"
cp -R "$BUNDLE" "$DEST/$APP.app"
echo "▸ Registering with Launch Services, Services menu and Finder"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST/$APP.app" || true
/System/Library/CoreServices/pbs -update 2>/dev/null || true
pluginkit -a "$DEST/$APP.app/Contents/PlugIns/ClementineFinder.appex" 2>/dev/null || true
pluginkit -e use -i app.clementine.mac.finder 2>/dev/null || true
./install-quick-actions.sh "$DEST/$APP.app"
echo "Installed to $DEST/$APP.app"
