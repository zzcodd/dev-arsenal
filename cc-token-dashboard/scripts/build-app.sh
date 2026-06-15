#!/bin/bash
# Build CCTokenDashboard.app — a double-clickable, menu-bar-only macOS app bundle.
#
#   ./scripts/build-app.sh            # release build into ./build/CCTokenDashboard.app
#   ./scripts/build-app.sh --install  # also copy it to /Applications
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="CCTokenDashboard"
BUNDLE="build/CCTokenDashboard.app"
CONFIG="release"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG" --product "$APP_NAME"

BIN=".build/$CONFIG/$APP_NAME"

echo "▸ Assembling ${BUNDLE} ..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"

# App icon: if you drop a 1024x1024 Resources/AppIcon.png, generate the .icns the
# system expects (a multi-size bundle) and embed it. CFBundleIconFile=AppIcon points to it.
if [[ -f Resources/AppIcon.png ]]; then
    echo "▸ Generating app icon from Resources/AppIcon.png ..."
    ICONSET="build/AppIcon.iconset"
    rm -rf "$ICONSET"; mkdir -p "$ICONSET"
    for SZ in 16 32 128 256 512; do
        sips -z "$SZ" "$SZ"        Resources/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}.png"    >/dev/null
        sips -z "$((SZ*2))" "$((SZ*2))" Resources/AppIcon.png --out "$ICONSET/icon_${SZ}x${SZ}@2x.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET"
else
    echo "  (no Resources/AppIcon.png — app keeps the default blank icon)"
fi

# Ad-hoc codesign so SMAppService (launch-at-login) and notifications behave.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || \
  echo "  (codesign skipped — app still runs)"

echo "✓ Built $BUNDLE"

if [[ "${1:-}" == "--install" ]]; then
    echo "▸ Installing to /Applications…"
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$BUNDLE" "/Applications/$APP_NAME.app"
    echo "✓ Installed. Launch from Spotlight or: open -a $APP_NAME"
fi

echo ""
echo "Run it now with:  open \"$BUNDLE\""
