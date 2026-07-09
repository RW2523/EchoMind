# App Store screenshots

Real, populated captures of the shipping UI (seeded with demo data). Dark navy
theme, on-device AI, no mockups.

| File | Screen | Suggested caption |
|---|---|---|
| `01-home.png` | Home — live status + hero | "Your meetings, remembered — privately." |
| `02-sessions.png` | Sessions grouped by AI category | "Similar meetings, auto-organized." |
| `03-ask.png` | Ask (ChatGPT-style chat) | "Ask your meetings anything." |
| `04-report.png` | Auto report + action items + continuity | "Instant summaries & action items." |
| `05-memory.png` | What EchoMind Remembers | "Context from every past meeting." |

## Sizes / regenerating

These were captured at **1206×2868** (iPhone 16 Pro, 6.3" class). App Store Connect
**requires a 6.9" set (1320×2868, iPhone 16 Pro Max)** as the primary display, and
optionally accepts the 6.5" set (1242×2688).

Regenerate at the required 6.9" size:

```
./AppStore/capture_screenshots.sh "iPhone 16 Pro Max"     # → 1320×2868
```

Or any other installed simulator:

```
./AppStore/capture_screenshots.sh "iPhone 15 Plus"        # 6.5" class
```

The demo data is seeded by the DEBUG `--demo-seed` launch argument (`DemoSeed.swift`);
individual screens are reached with `--screen sessions|ask|report|memory` (`RootView`).

## Optional: add caption frames

These raw screenshots upload as-is. For marketing frames (device bezel + caption
bar), drop them into a tool like [fastlane frameit], Screenshots.pro, or a Figma
template — but Apple accepts plain device screenshots too.
