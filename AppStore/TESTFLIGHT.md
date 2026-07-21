# TestFlight — the complete runbook

Getting EchoMind onto other people's iPhones, start to finish.

## Where things stand

| | |
|---|---|
| App code, tests (309), CI | ✅ green |
| Signed `.xcarchive` builds on this Mac | ✅ verified |
| Privacy Policy + Support URLs (required by Apple) | ✅ **live** — see below |
| Deployment target | ✅ iOS 26.0 (was 26.5, which would have excluded testers) |
| Screenshots, metadata, privacy manifest | ✅ prepared |
| **Apple Developer Program membership** | ❌ **the one blocker — $99/yr, only you can do it** |
| Device validation pass | ⏳ recommended before external testers |

**Required URLs (already live):**
- Privacy Policy — https://rw2523.github.io/EchoMind/privacy.html
- Support — https://rw2523.github.io/EchoMind/support.html

---

## Phase 1 — Enroll in the Apple Developer Program

*You, ~30 min of forms + 24–48 h for Apple to approve.*

1. Go to **[developer.apple.com/programs](https://developer.apple.com/programs)** → **Enroll**.
2. Sign in with the Apple ID that should own the app.
3. Choose **Individual / Sole Proprietor** — it's the fast path. (*Organization* requires
   a D-U-N-S number and can take weeks. Pick Individual unless you specifically need a
   company name shown as the seller.)
4. Pay **$99/year**. Wait for the approval email.

> A free Apple account can build and run on your own device but **cannot** create App
> Store provisioning profiles. That's the exact error this project hit:
> *"Team does not have permission to create iOS App Store provisioning profiles."*
> Nothing in the code can work around it.

## Phase 2 — Create the app record

*You, ~20 min, once enrollment is approved.*

1. **Register the App ID:** [developer.apple.com/account](https://developer.apple.com/account)
   → Certificates, IDs & Profiles → **Identifiers** → **+** → App IDs → App →
   explicit Bundle ID `com.ajace.EchoMind`. (Xcode's automatic signing usually creates
   this on first archive — come here only if it complains.)
2. **Create the app:** [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
   → **My Apps** → **+** → **New App**:
   - Platform: **iOS**
   - Name: **EchoMind** *(must be unique across the whole App Store — if it's taken,
     pick a variant now; this is also the name users see)*
   - Primary language: **English (U.S.)**
   - Bundle ID: **com.ajace.EchoMind**
   - SKU: anything unique, e.g. `echomind-1` (internal only, never shown)
3. In **App Information**, paste the two URLs above and set the category
   (suggested: **Productivity**, secondary **Business**).
4. **App Privacy** → **"No, we do not collect data from this app."** True for EchoMind
   and provable — the app makes zero network calls, enforced by `NetworkAuditTests`.
   Tracking: **No**.

Copy for every text field is in [METADATA.md](METADATA.md).

## Phase 3 — Upload a build

*Two commands; Xcode does the signing.*

Sign into the enrolled Apple ID first: Xcode ▸ Settings ▸ Accounts (team `FDL6ACC4VS`).

```bash
./AppStore/bump_build.sh                                    # 1 → 2 (unique build number)
./AppStore/build_ipa.sh "$(./AppStore/bump_build.sh --show)"
```

That produces a signed App Store `.ipa` in `build/export/`. Upload it either way:

- **Xcode:** Window ▸ Organizer ▸ Archives ▸ **Distribute App** ▸ App Store Connect ▸ Upload
- **Transporter** (free, Mac App Store): drag the `.ipa` in and press Deliver

Then wait ~5–15 min for "Processing" to finish under App Store Connect ▸ TestFlight.

> **Every upload needs a higher build number than the last.** That's what
> `bump_build.sh` is for, and it refuses to go backwards. Reusing a number is the most
> common second-upload failure.

Export compliance is already answered in `Info.plist`
(`ITSAppUsesNonExemptEncryption = NO`), so uploads won't stall on that prompt.

## Phase 4 — Internal testers (fast, no review)

For you and a few close collaborators. **Up to 100 people, available minutes after
processing, no Apple review.**

1. App Store Connect → **Users and Access** → invite each person as **App Manager** or
   **Developer** (they need an Apple ID and must accept the emailed invite).
2. → **TestFlight** tab → **Internal Testing** → create a group → add those users →
   tick the build.
3. They install the free **TestFlight** app from the App Store, and EchoMind appears.

## Phase 5 — External testers + a public link

This is how you let people test it at scale: **up to 10,000 testers**, and a link
anyone can open.

1. TestFlight tab → **External Testing** → **+** → create a group (e.g. "Public Beta").
2. Add the build to the group.
3. Fill **Test Information** (required once):
   - *What to Test* — e.g. "Record a short meeting, check the auto-report and action
     items, then try Ask and Voice mode."
   - *Beta App Description*, a feedback email, and the privacy policy URL above.
   - **Demo account: not required** — EchoMind has no sign-in. Say so in the notes.
4. **Submit for Beta App Review.** The first build takes ~24–48 h; later builds of the
   same version usually skip review.
5. Once approved, enable **Public Link**. You get a URL like
   `https://testflight.apple.com/join/XXXXXXXX` — share it anywhere. You can cap how
   many testers may join.

Testers open the link on an iPhone → it installs TestFlight → then EchoMind.

**Tell your testers they need:** an iPhone on **iOS 26.0+**, and for the AI features
(summaries, grouping, Ask, Voice) an **Apple-Intelligence-capable iPhone** with Apple
Intelligence switched on. Recording, transcription, playback, and export work on any
supported iPhone.

## Before you open the public link

Run [DEVICE_TEST_CHECKLIST.md](DEVICE_TEST_CHECKLIST.md) on a real iPhone. Simulators
can't validate the mic/speech/voice paths, and that's exactly where device-only bugs
hide — the Voice-mode crash found on 10 Jul was one of them. Internal TestFlight is the
right place to shake those out first.

## Housekeeping

- **Builds expire after 90 days.** Upload a fresh one to keep testers running.
- **Version vs build:** `MARKETING_VERSION` (1.0) is what users see; the build number
  only has to increase. Bump the version for a real release, the build for every upload.
- **Feedback:** testers can send screenshots and notes from inside TestFlight — they
  land in App Store Connect ▸ TestFlight ▸ Feedback. Crashes show in Xcode ▸ Organizer.

## Common upload errors

| Error | Fix |
|---|---|
| "does not have permission to create iOS App Store provisioning profiles" | Not enrolled in the paid program yet (Phase 1) |
| "The bundle version must be higher than the previously uploaded version" | `./AppStore/bump_build.sh`, then re-archive |
| "No provider associated with App Store Connect user" | Free account, or the wrong Apple ID is signed into Xcode |
| Missing `Info.plist` encryption value | Already handled — `ITSAppUsesNonExemptEncryption = NO` |
| App record won't save — privacy URL rejected | The URL must be publicly reachable; ours is live (verified 200) |

## What was already fixed to get here

- Removed the app-wide `com.apple.developer.default-data-protection` entitlement that
  broke automatic signing (it required a Data Protection capability on the App ID). File
  protection is now enforced **at runtime** on the database *and* the audio directory
  (`.completeUnlessOpen`) — same privacy guarantee, simpler signing. This is why the
  archive builds.
- Lowered the deployment target from iOS 26.5 → **26.0**, so testers on 26.0–26.4 can
  install at all.
- Published the required Privacy Policy and Support pages (both were 404s).
- Added `AppStore/ExportOptions.plist`, `build_ipa.sh` (archive + export), and
  `bump_build.sh` (safe build-number increments).

## If you enroll under a different team

The bundle id and team `FDL6ACC4VS` are already set in the project. Under a different
team, update `DEVELOPMENT_TEAM` in the project's build settings and `teamID` in
`AppStore/ExportOptions.plist`.
