#!/bin/bash
# Builds a signed App Store .ipa for TestFlight/App Store upload.
#
# PREREQUISITES (one-time, in YOUR Apple account):
#   1. Paid Apple Developer Program membership (developer.apple.com/programs — $99/yr).
#   2. An app record for bundle id "com.ajace.EchoMind" in App Store Connect.
#   3. Signed into that Apple ID in Xcode ▸ Settings ▸ Accounts (team FDL6ACC4VS).
#
# USAGE:  ./AppStore/build_ipa.sh [BUILD_NUMBER]
#   BUILD_NUMBER defaults to a unix timestamp so every upload is unique.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD="${1:-$(date +%s)}"
echo "▸ Archiving EchoMind (build $BUILD)…"
rm -rf build/EchoMind.xcarchive build/export

xcodebuild -scheme EchoMind -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/EchoMind.xcarchive \
  CURRENT_PROJECT_VERSION="$BUILD" \
  archive -allowProvisioningUpdates

echo "▸ Exporting App Store .ipa…"
xcodebuild -exportArchive \
  -archivePath build/EchoMind.xcarchive \
  -exportOptionsPlist AppStore/ExportOptions.plist \
  -exportPath build/export \
  -allowProvisioningUpdates

echo "✅ Done: build/export/EchoMind.ipa"
echo ""
echo "Upload to TestFlight, either:"
echo "  • Xcode Organizer (easiest): Window ▸ Organizer ▸ select the archive ▸"
echo "    Distribute App ▸ App Store Connect ▸ Upload."
echo "  • CLI:  xcrun altool --upload-app -f build/export/EchoMind.ipa -t ios \\"
echo "            --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>   # App Store Connect API key"
