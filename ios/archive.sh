#!/usr/bin/env bash
# archive the iOS app for TestFlight / the App Store, and optionally upload it.
# needs a paid Apple Developer Program account — a free Apple ID can only run the app
# straight from Xcode (see docs/ios-deploy.md).
set -euo pipefail
cd "$(dirname "$0")/.."

# usage: ./ios/archive.sh [--upload]
#   --upload   ship the .ipa to App Store Connect instead of leaving it on disk
UPLOAD=0
[[ "${1:-}" == "--upload" ]] && UPLOAD=1

PROJECT="ios/ClaudeUsage.xcodeproj"
SCHEME="ClaudeUsage"
OUT="build"
ARCHIVE="$OUT/ClaudeUsage.xcarchive"

# the team can't be inferred — automatic signing needs to know who's asking.
TEAM="${DEVELOPMENT_TEAM:-}"
if [[ -z "$TEAM" ]]; then
    echo "✗ set DEVELOPMENT_TEAM to your 10-char team id (Xcode → Settings → Accounts,"
    echo "  or developer.apple.com/account → Membership details)."
    exit 1
fi

echo "▸ archiving (team $TEAM)…"
rm -rf "$ARCHIVE"
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE" \
    DEVELOPMENT_TEAM="$TEAM" \
    CODE_SIGN_STYLE=Automatic \
    -allowProvisioningUpdates

# "destination: upload" hands the build straight to App Store Connect; "export" just writes
# the .ipa. either way the method is app-store-connect — that's what TestFlight feeds on.
PLIST="$OUT/ExportOptions.plist"
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key><string>app-store-connect</string>
	<key>teamID</key><string>$TEAM</string>
	<key>destination</key><string>$([[ "$UPLOAD" == 1 ]] && echo upload || echo export)</string>
	<key>uploadSymbols</key><true/>
</dict>
</plist>
PLISTEOF

AUTH=()
if [[ "$UPLOAD" == 1 ]]; then
    : "${ASC_KEY_ID:?set ASC_KEY_ID — App Store Connect API key id}"
    : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID — shown above the key list in App Store Connect}"
    # xcodebuild looks in ~/.appstoreconnect/private_keys for AuthKey_<id>.p8 by default,
    # so only the ids are needed here.
    AUTH=(-authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID"
          -authenticationKeyPath "$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8")
    echo "▸ exporting + uploading to App Store Connect…"
else
    echo "▸ exporting .ipa…"
fi

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$OUT" \
    -exportOptionsPlist "$PLIST" \
    -allowProvisioningUpdates \
    "${AUTH[@]}"

if [[ "$UPLOAD" == 1 ]]; then
    echo "✓ uploaded — App Store Connect → TestFlight, ~5-15 min of processing"
else
    echo "✓ $OUT/ClaudeUsage.ipa"
    echo "  upload: ./ios/archive.sh --upload   (or Xcode → Product → Archive → Distribute)"
fi
