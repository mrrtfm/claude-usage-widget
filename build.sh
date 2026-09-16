#!/usr/bin/env bash
# build ClaudeUsage.app — compiles the SPM executable, wraps it in an .app bundle
# with an LSUIElement Info.plist (menu-bar only, no dock), ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"

# usage: ./build.sh [config] [--install]
#   config    debug | release (default: release)
#   --install copy the built .app into /Applications and relaunch it
CONFIG="release"
INSTALL=0
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        *)         CONFIG="$arg" ;;
    esac
done

APP="ClaudeUsage.app"
BUNDLE_ID="com.laszlo.ClaudeUsage"
INSTALL_DIR="/Applications"

echo "▸ swift build ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ClaudeUsage"

echo "▸ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"

# app icon — shows in Finder/Spotlight/Applications (menu-bar app has no dock icon).
# regen from tools/gen-icon.swift; see the header there for the iconset loop.
[[ -f AppIcon.icns ]] && cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Usage</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleExecutable</key><string>ClaudeUsage</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "▸ ad-hoc signing…"
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "  (codesign skipped)"

echo "✓ built $APP"

if [[ "$INSTALL" == 1 ]]; then
    DEST="$INSTALL_DIR/$APP"
    echo "▸ installing to ${DEST}…"
    # quit any running copy first — can't overwrite a live bundle cleanly
    osascript -e 'quit app "Claude Usage"' >/dev/null 2>&1 || true
    rm -rf "$DEST"
    cp -R "$APP" "$DEST"
    open "$DEST"
    echo "✓ installed & launched — look for the gauge in the menu bar"
else
    echo "  run:     open $APP     — or — ./$APP/Contents/MacOS/ClaudeUsage"
    echo "  install: ./build.sh --install   (-> $INSTALL_DIR)"
fi
