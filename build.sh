#!/usr/bin/env bash
# build ClaudeUsage.app — compiles the SPM executable, wraps it in an .app bundle
# with an LSUIElement Info.plist (menu-bar only, no dock), ad-hoc signs it.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP="ClaudeUsage.app"
BUNDLE_ID="com.laszlo.ClaudeUsage"

echo "▸ swift build ($CONFIG)…"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/ClaudeUsage"

echo "▸ assembling ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ClaudeUsage"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Claude Usage</string>
    <key>CFBundleDisplayName</key><string>Claude Usage</string>
    <key>CFBundleExecutable</key><string>ClaudeUsage</string>
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
echo "  run:  open $APP     — or — ./$APP/Contents/MacOS/ClaudeUsage"
