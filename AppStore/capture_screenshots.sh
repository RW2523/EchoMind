#!/bin/bash
# Regenerate App Store screenshots with demo data (DEBUG build).
#
# Usage:  ./AppStore/capture_screenshots.sh ["iPhone 16 Pro Max"]
#   Default sim is "iPhone 16 Pro Max" → 1320×2868 = the REQUIRED 6.9" App Store size.
#   Pass another installed simulator name to target a different display size.
set -euo pipefail
cd "$(dirname "$0")/.."

SIM="${1:-iPhone 16 Pro Max}"
OUT="AppStore/screenshots"
BID="com.ajace.EchoMind"
mkdir -p "$OUT"

echo "▸ Building (Debug) for $SIM…"
xcodebuild -scheme EchoMind -destination "platform=iOS Simulator,name=$SIM" build >/dev/null
APP=$(find ~/Library/Developer/Xcode/DerivedData/EchoMind-*/Build/Products/Debug-iphonesimulator -maxdepth 1 -name "EchoMind.app" | head -1)

xcrun simctl boot "$SIM" 2>/dev/null || true
sleep 6
xcrun simctl uninstall booted "$BID" 2>/dev/null || true
xcrun simctl install booted "$APP"

echo "▸ Seeding demo data…"
xcrun simctl launch booted "$BID" --skip-onboarding --demo-seed >/dev/null
sleep 8

# Each screen: full terminate → cold launch with --screen (bypasses tab-state
# restoration) → settle → capture.
shot() {
  xcrun simctl terminate booted "$BID" 2>/dev/null || true; sleep 3
  xcrun simctl launch booted "$BID" --skip-onboarding ${2:+--screen "$2"} >/dev/null
  sleep 6
  xcrun simctl io booted screenshot "$OUT/$1.png"
  echo "  ✅ $1"
}
shot 01-home           # (no --screen → Home tab, shows the tab bar)
shot 02-sessions sessions
shot 03-ask ask
shot 04-report report
shot 05-memory memory

echo "▸ Done — $(sips -g pixelWidth -g pixelHeight "$OUT/01-home.png" 2>/dev/null | grep -o '[0-9]*' | paste -sd× -) in $OUT/"
