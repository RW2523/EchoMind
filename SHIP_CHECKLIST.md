# EchoMind — TestFlight Ship Checklist

Phases 1–10 are implemented, building, and unit-tested (see git log). The items
below are the **human-only** steps Claude Code cannot perform (BUILD_PLAN.md §7.4).

## Before archiving
- [ ] Run the full manual matrix in `TESTLOG.md` on a Tier A device (+ Tier B / AI-off for rows 7–8).
- [ ] **Launch screen:** in the target's Info tab, add the `UILaunchScreen` key (solid
      background color + the app icon; no storyboard). This lives in the `.xcodeproj`
      as an `INFOPLIST_KEY_*` build setting, so it's a human edit. (The icon asset is
      already in `Assets.xcassets/AppIcon.appiconset` — a placeholder; replace with a
      designed icon before public release.)
- [ ] **Minimum deployment target:** confirm it's **iOS 26.0** (currently 26.5 — set
      General → Minimum Deployments → iOS 26.0 to support iPhone 11 / SE 2nd gen).
- [ ] **Swift Language Version:** confirm the app target is Swift 6.

## App Store Connect
- [ ] Create the app record; bundle ID = `com.ajace.EchoMind`.
- [ ] **App Privacy:** declare **Data Not Collected** (true in V1; the `NetworkAuditTests`
      guard enforces zero networking).
- [ ] **Export compliance:** set `ITSAppUsesNonExemptEncryption = NO` (standard OS
      encryption only) in the Info tab.

## Upload + TestFlight
- [ ] Product → Archive (Release) → Validate → Upload.
- [ ] Add internal testers; "What to Test" → point at `TESTLOG.md` rows.
- [ ] Reviewer note: explain the onboarding consent flow and that recording is
      user-initiated only (pre-empts App Review questions on recording apps).

## Known follow-ups (V1.1, BUILD_PLAN.md §10)
- PCC / third-party model gateway behind the existing `ModelGateway` (cloud opt-in, default off).
- MiniLM Core ML embeddings if the retrieval eval scores < 7/10.
- Native `tokenCount(for:)` when iOS 26.4 is the floor (single fallback constant in `TokenBudgeter`).
