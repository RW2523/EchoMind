#!/bin/bash
# Publish the staged wiki pages to the GitHub Wiki.
# Prereq: Wikis must be ENABLED (repo Settings ▸ Features ▸ Wikis). Note that GitHub
# only allows wikis on PRIVATE repos with a paid plan (Pro/Team) — or on any PUBLIC repo.
# Then create the first page once via the web UI to initialise the wiki repo.
set -euo pipefail
cd "$(dirname "$0")"
TMP=$(mktemp -d)
git clone https://github.com/RW2523/EchoMind.wiki.git "$TMP"
cp Home.md User-Guide.md Architecture.md FAQ.md _Sidebar.md "$TMP/"
cd "$TMP"
git add -A
git commit -m "Update wiki from repo/wiki" || { echo "no changes"; exit 0; }
git push
echo "✅ Wiki updated: https://github.com/RW2523/EchoMind/wiki"
