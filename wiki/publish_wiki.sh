#!/bin/bash
# Publish the staged wiki pages to the GitHub Wiki.
#
# One-time prereq (GitHub has no API for this — must be done signed in on the web):
#   1. Repo Settings ▸ Features ▸ Wikis = ON  (already enabled for this repo).
#   2. Open https://github.com/RW2523/EchoMind/wiki ▸ "Create the first page" ▸ Save
#      (any content — this script overwrites it). This initialises the wiki git repo.
#
# Then run this script. It authenticates with your `gh` token if available, so no
# interactive credential prompt; falls back to plain https otherwise.
set -euo pipefail
cd "$(dirname "$0")"

REPO="RW2523/EchoMind"
if command -v gh >/dev/null 2>&1 && TOKEN=$(gh auth token 2>/dev/null) && [ -n "$TOKEN" ]; then
  WIKI_URL="https://x-access-token:${TOKEN}@github.com/${REPO}.wiki.git"
else
  WIKI_URL="https://github.com/${REPO}.wiki.git"
fi

TMP=$(mktemp -d)
if ! git clone "$WIKI_URL" "$TMP" 2>/dev/null; then
  echo "❌ Could not clone the wiki repo. It isn't initialised yet."
  echo "   Open https://github.com/${REPO}/wiki and click 'Create the first page' (save any content), then re-run this script."
  exit 1
fi

cp Home.md User-Guide.md Architecture.md FAQ.md _Sidebar.md "$TMP/"
cd "$TMP"
git add -A
git commit -m "Update wiki from repo/wiki" || { echo "✓ Wiki already up to date."; exit 0; }
git push
echo "✅ Wiki updated: https://github.com/${REPO}/wiki"
