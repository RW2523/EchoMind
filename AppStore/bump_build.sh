#!/bin/bash
# Increment the app's build number (CURRENT_PROJECT_VERSION).
#
# WHY: App Store Connect rejects an upload whose build number was already used for
# the same version string. Every TestFlight upload therefore needs a new, higher
# build number — this is the #1 thing that trips people up on their second upload.
#
# USAGE:
#   ./AppStore/bump_build.sh            # 3 → 4
#   ./AppStore/bump_build.sh 42         # set explicitly to 42
#   ./AppStore/bump_build.sh --show     # print the current number, change nothing
#
# Then archive with that number:
#   ./AppStore/build_ipa.sh "$(./AppStore/bump_build.sh --show)"
set -euo pipefail
cd "$(dirname "$0")/.."

PBX="EchoMind.xcodeproj/project.pbxproj"
CURRENT=$(grep -m1 -o 'CURRENT_PROJECT_VERSION = [0-9][0-9]*;' "$PBX" | grep -o '[0-9][0-9]*')

if [ "${1:-}" = "--show" ]; then
  echo "$CURRENT"
  exit 0
fi

if [ $# -ge 1 ]; then
  NEXT="$1"
  case "$NEXT" in
    ''|*[!0-9]*) echo "error: build number must be a positive integer" >&2; exit 1 ;;
  esac
  if [ "$NEXT" -le "$CURRENT" ]; then
    echo "error: $NEXT is not higher than the current build ($CURRENT)." >&2
    echo "       App Store Connect requires each upload to increase." >&2
    exit 1
  fi
else
  NEXT=$((CURRENT + 1))
fi

# Every build configuration must agree, so replace all occurrences.
sed -i '' "s/CURRENT_PROJECT_VERSION = ${CURRENT};/CURRENT_PROJECT_VERSION = ${NEXT};/g" "$PBX"

VERSION=$(grep -m1 -o 'MARKETING_VERSION = [^;]*;' "$PBX" | sed 's/MARKETING_VERSION = //; s/;//')
echo "▸ Build number: $CURRENT → $NEXT   (version $VERSION)"
echo "  Archive it with:  ./AppStore/build_ipa.sh $NEXT"
echo "  Commit it with:   git commit -am \"Bump build to $NEXT\""
