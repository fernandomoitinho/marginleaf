#!/usr/bin/env bash
# Builds build/Marginleaf.app and build/Marginleaf.dmg (Apple Silicon only). Run on macOS.
#   VERSION=0.1.0 BUILD=1 bash scripts/make-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
BUILD="${BUILD:-1}"

swift build -c release --arch arm64
BIN="$(swift build -c release --arch arm64 --show-bin-path)/Marginleaf"

rm -rf build
APP="build/Marginleaf.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Marginleaf"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" Resources/Info.plist > "$APP/Contents/Info.plist"
plutil -lint "$APP/Contents/Info.plist"

# Icon: Resources/AppIcon.icns is pre-rendered with Lanczos resampling from AppIcon.png (1024px).
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature. Not an Apple Developer ID, so Gatekeeper still asks on first launch.
codesign --force --sign - "$APP"

# Disk image: the app and an Applications shortcut, on a background that says "drag here".
# create-dmg (Homebrew) lays the window out; if it is not installed, fall back to a plain image.
DMG="build/Marginleaf.dmg"
STAGE="build/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
if command -v create-dmg >/dev/null 2>&1 && create-dmg \
    --volname "Marginleaf" \
    --background "Resources/dmg-background.png" \
    --window-pos 200 120 --window-size 600 400 \
    --icon-size 110 \
    --icon "Marginleaf.app" 150 200 \
    --app-drop-link 450 200 \
    --hide-extension "Marginleaf.app" \
    --no-internet-enable \
    "$DMG" "$STAGE"; then
  echo "dmg: styled with create-dmg"
else
  echo "dmg: create-dmg unavailable or failed, using a plain image"
  rm -f "$DMG"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Marginleaf" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
fi
rm -rf "$STAGE"

echo "Built Marginleaf $VERSION ($BUILD)"
du -sh "$APP" build/Marginleaf.dmg
