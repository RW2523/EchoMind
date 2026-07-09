# TestFlight — where the build stands & how to finish it

## Status: the app is build-ready. One account blocker remains.

I verified the whole build pipeline on this Mac:

| Step | Result |
|---|---|
| Compiles for real device (arm64), Release | ✅ clean (first-ever device build) |
| Signing (development) | ✅ works |
| **Signed `.xcarchive` builds** | ✅ **created** (`build/EchoMind.xcarchive`) |
| Archive contents | ✅ privacy manifest, icon, v1.0, background-audio all present |
| 261 tests | ✅ green |
| **App Store export / upload** | ❌ **blocked — see below** |

### The one blocker (not fixable in code — it's your Apple account)
Export failed with:
> Team "Richard Watson S A" does not have permission to create "iOS App Store"
> provisioning profiles · No provider associated with App Store Connect user

That's the exact signature of a **free Apple account**. A free account can build and
run on your own device, but **TestFlight/App Store distribution requires the paid
Apple Developer Program ($99/yr)**. No machine can produce a TestFlight build with
this account until it's enrolled — this isn't a code problem.

## What I already fixed to get here
- Removed the app-wide `com.apple.developer.default-data-protection` entitlement that
  was breaking automatic signing (it required a Data-Protection capability on the App
  ID). File protection is now enforced **at runtime** on both the SwiftData database
  *and* the audio directory (`.completeUnlessOpen`) — same privacy, simpler signing.
  This is why the archive now builds.
- Added `AppStore/ExportOptions.plist` (App Store method, team FDL6ACC4VS, automatic).
- Added `AppStore/build_ipa.sh` (one-command archive + export).

## Finish it (your steps, ~1–2 h of work + Apple's queue)

1. **Enroll in the Apple Developer Program** — https://developer.apple.com/programs
   (paid; individual or organization). Enrollment can take a few hours to ~2 days.
2. **App Store Connect** — create the app record:
   - My Apps ▸ + ▸ New App ▸ Platform iOS ▸ Name **EchoMind** (check availability;
     fallbacks in `METADATA.md`) ▸ Bundle ID **com.ajace.EchoMind** ▸ SKU `echomind`.
3. **Xcode ▸ Settings ▸ Accounts** — sign in with that Apple ID; confirm team
   **FDL6ACC4VS** shows the paid membership.
4. **Build & upload** — easiest is the GUI:
   - Xcode ▸ Product ▸ **Archive** (scheme EchoMind, "Any iOS Device").
   - Organizer opens ▸ **Distribute App** ▸ **App Store Connect** ▸ **Upload**.
   - Or run: `./AppStore/build_ipa.sh` then upload `build/export/EchoMind.ipa` via
     Organizer or `xcrun altool` (see the script's footer).
5. **App Store Connect ▸ TestFlight** — the build appears after processing (~5–15 min).
   Answer the encryption question (already exempt via `ITSAppUsesNonExemptEncryption`).
   Add yourself + testers to **Internal Testing** → install via the TestFlight app.
6. **Run the device checklist** — `AppStore/DEVICE_TEST_CHECKLIST.md` on the TestFlight
   build. Report failures; I fix same-day.

## Then: submit for review
Once the device checklist's P0s pass, use `AppStore/METADATA.md` (description,
keywords, review notes) + screenshots, host `PRIVACY_POLICY.md`, and submit. Review
notes pre-answer the likely friction (on-device AI, background mic, device floor).

## Reminder on `com.ajace.EchoMind`
The bundle id + team `FDL6ACC4VS` are already set in the project. If you enroll under
a **different** team, update `DEVELOPMENT_TEAM` (project settings) and `teamID` in
`AppStore/ExportOptions.plist`.
