---
name: build-check
description: Build EchoMind for the simulator and fix any compile errors from recent changes
---
Run: xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -60
If it fails, read the errors, fix them, and rebuild until clean.
Never delete failing code or silence warnings just to make the build pass.
