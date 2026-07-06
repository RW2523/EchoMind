# EchoMind — End-to-End Build Plan

**What this is:** the complete, executable engineering plan to take EchoMind from this machine's current state (no usable Xcode, no project, no repo) to an internal TestFlight build. It expands the product/architecture spec in [echomind-claude-code-execution-plan.md](echomind-claude-code-execution-plan.md) — referred to throughout as **PLAN.md**, the constraint authority — into file-level work breakdowns, build order, human-vs-Claude-Code task splits, acceptance gates, a day-by-day schedule, and a risk register.

**Environment audit (2026-07-06), which this plan is built against:**

- This folder contains only the spec document. No Xcode project, no git repository, no `CLAUDE.md` yet.
- macOS 15.5 on an M4 / 16 GB Mac. **Xcode 16.4 is installed but unusable for this project**: it ships the iOS 18 SDK (no iOS 26, no SpeechAnalyzer/FoundationModels), and `xcode-select` points at Command Line Tools anyway, so `xcodebuild`/`simctl` don't currently resolve. Upgrading to Xcode 26.x is a real Day-0 work item (§1).
- ~~**Disk space is a hard Day-0 blocker:** only ~11–20 GB free.~~ **RESOLVED 2026-07-06:** now **73.9 GB free** after deleting Docker Desktop's 35 GB VM disk + caches (see §1 Step 0). No longer blocks the Xcode 26 install.
- iOS 26 is the current shipping major version; iOS 27 (the V1.1 cloud path) is expected fall 2026.

**Hard constraints inherited from PLAN.md — nothing below relaxes them:**
Swift 6 / SwiftUI / SwiftData, iOS 26.0 minimum, zero third-party packages, zero network calls, SpeechAnalyzer transcription stack, 4,096-token model context with the §3 budgets, Tier A/B device model, one fresh `LanguageModelSession` per call, MVVM + protocol services, never edit the `.xcodeproj`.

**How to use this document:**

1. Complete §1 (Phase 0) by hand where marked **Human** — Xcode install, project creation, signing, capabilities. Everything marked **CC** is a Claude Code task.
2. Then run one Claude Code session per phase, plan mode first, using PLAN.md §7's paste-ready prompts augmented by the corresponding section here.
3. Do not pass a section's **acceptance gate** without the listed device verification — audio, speech, and Foundation Models behavior cannot be judged from the simulator.
4. Commit at every green gate; `/clear` between phases.

**Contents**

| § | Covers | Spec phases |
|---|---|---|
| 1 | Machine & project bootstrap | Phase 0 (prereqs §4) |
| 2 | Storage foundation, navigation, onboarding & consent | Phase 1 |
| 3 | Audio engine, background recording, live transcription | Phases 2–3 |
| 4 | Sessions feature & document import | Phases 4 & 6 |
| 5 | AI core: gateway, token budgeter, summarizer | Phase 5 |
| 6 | Chunking, embeddings, vector search & Ask | Phases 7–8 |
| 7 | Privacy/settings, hardening, test matrix, schedule, risks | Phases 9–10 |

Sequencing note: §4 covers spec Phases 4 *and* 6 together because both are pure CRUD/UI with shared contracts; the AI core (§5, spec Phase 5) sits between them in the spec's numbering but depends only on Phases 1–4. The dependency graph and day-by-day ordering live in §7.

---

## 1. Phase 0 — Machine & Project Bootstrap

Goal: go from this machine's current state to a **committed, building, signed empty app running on a real iPhone**, with the repo scaffolded so every later phase is pure Claude Code work inside synchronized folder groups. Nothing in Phases 1–10 starts until the acceptance gate at the end of this section is green.

### 1.1 Audited machine state (as of 2026-07-06)

| Fact | Value | Impact |
|---|---|---|
| macOS | **15.7.7 (24G720)** — ✅ meets requirement | **Verified against Apple's support page (2026-07-06):** Xcode 26.0–26.3 require **macOS Sequoia 15.6+** (15.7.7 satisfies this); Xcode 26.4+ require **macOS Tahoe 26.2**. Machine updated 15.5 → 15.7.7. Remaining Day-0 action: install **Xcode 26.3** (newest on Sequoia, ships the **iOS 26.2 SDK** — satisfies this project's iOS 26.0 floor). Do **not** upgrade to Tahoe for V1. |
| Xcode | **16.4 installed** (`/Applications/Xcode.app`, 5.2 GB) | Ships the iOS 18 SDK only — cannot build for iOS 26, cannot use SpeechAnalyzer/FoundationModels. Must install Xcode 26.x side-by-side (or replace). |
| `xcode-select -p` | `/Library/Developer/CommandLineTools` | Points at bare CLT; `simctl`/`xcodebuild` against a real SDK unavailable. Must be switched after install. |
| Free disk space | **~74 GB free** (was 12.5 GB — **resolved 2026-07-06**, see Step 0) | Was the primary blocker at 12.5 GB. Root cause was **not** Xcode caches — it was Docker Desktop's VM disk (`Docker.raw`, 35 GB real). That was deleted (full Docker reset) plus ~3 GB of user caches; macOS auto-purged the rest. Now clears the **≥ 60 GB before starting** target with headroom. Xcode 26 xip (~3.5 GB) expands to ~15–20 GB, iOS 26 simulator runtime adds ~8 GB, device support more; the acceptance gate requires ≥ 30 GB free *after* installs. |
| Node / npm | v26.3.0 / 11.16.0 | Claude Code installable (`npm i -g @anthropic-ai/claude-code`). |
| git | 2.39.5 (Apple) | Fine. No repo exists yet in `~/Documents/mob`. |
| Project | None. Only `echomind-claude-code-execution-plan.md` in `~/Documents/mob` | Becomes `PLAN.md` at repo root. |

### 1.2 Ordered steps

Legend: **[H]** human/GUI-only, **[C]** Claude Code (terminal), **[H→C]** human does it, Claude Code verifies.

#### Step 0 — Free disk space **[H]** — ✅ DONE on this machine (2026-07-06)
Target: **≥ 60 GB free** on the data volume. Rationale: the installs below consume ~25–30 GB (Xcode 26 expands to ~15–20 GB, iOS 26 simulator runtime ~8 GB, device support more, plus the ~3.5 GB xip until deleted), and the Phase-0 acceptance gate requires **≥ 30 GB free *after* all installs** — so freeing only 50 GB would leave ~20–25 GB and fail the gate.

**What actually freed the space here (record for reproducibility):** the machine started at **12.5 GB free**. A size audit found the culprit was **not** Xcode/dev caches (those totalled < 9 GB) — it was **Docker Desktop's Linux VM disk**, `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`, using **35 GB** of real disk (245 GB sparse). The fix, in order:
1. Cleared ~3 GB of safe regenerable user caches (`~/Library/Caches/{Homebrew,pip,node-gyp,Google,com.openai.atlas,...}`). macOS also auto-purged ~10 GB of purgeable space on its own during this.
2. **Full Docker reset:** quit Docker Desktop gracefully (`osascript -e 'quit app "Docker"'`, confirm `com.docker.backend`/`com.docker.virtualization` exited), then `rm -f` the `Docker.raw` file. This wipes all Docker images/containers/volumes/build-cache (Docker recreates a fresh empty VM on next launch; source `Dockerfile`/compose files are untouched). Reclaimed the full 35 GB.

Result: **73.9 GB free** — target cleared. General guidance if you must repeat this on another machine: audit with Spotlight first (`mdfind 'kMDItemFSSize > 1073741824'` finds >1 GB files instantly — far faster than `du`, which times out on dense home dirs), because the space hog is machine-specific (here Docker; elsewhere it may be Photos, iCloud Drive local copies, or old Xcodes). If still short, `sudo tmutil deletelocalsnapshots /` removes OS-update rollback snapshots, and deleting Xcode 16.4 (~5 GB) after 26.x is proven working recovers more. Do not start the install below under ~40 GB free — xip expansion alone can wedge the volume.

#### Step 1 — Update macOS, then install Xcode **[H, verify C]**
0. **[H] Update macOS to ≥ 15.6** — ✅ DONE (machine is on **15.7.7** as of 2026-07-06). Verified against Apple's support page: **no Xcode 26 runs on 15.5** — 26.0–26.3 need macOS **Sequoia 15.6+** (15.7.7 satisfies); 26.4+ need macOS **Tahoe 26.2**. **Do not jump to Tahoe 26** unless you deliberately want Xcode 26.4+ — Sequoia + Xcode 26.3 is the lower-risk path for V1.
1. **[H]** Install **Xcode 26.3** — the newest release that still runs on Sequoia 15.6, shipping the **iOS 26.2 SDK** (this project needs iOS 26.0; 26.2 SDK is fully compatible). Getting the *newest Sequoia-compatible* Xcode (rather than 26.0) maximizes bug-fixes for the SpeechAnalyzer/FoundationModels stack without forcing a Tahoe upgrade.
2. **[H]** Download via App Store *or* developer.apple.com/download (xip — pick the version explicitly labelled "requires macOS 15.6"). The xip route lets you keep 16.4 side-by-side: expand, rename to `/Applications/Xcode-26.3.app`, then **delete the xip** (required — its ~3.5 GB is counted in Step 0's disk budget). App Store installs replace `/Applications/Xcode.app` (16.4) in place, which is fine now that disk isn't tight.
3. **[H or C]** Switch the toolchain and accept the license (needs sudo → human types the password, but Claude Code can compose/verify):
   ```bash
   sudo xcode-select -s /Applications/Xcode-26.x.app/Contents/Developer
   sudo xcodebuild -license accept
   xcodebuild -runFirstLaunch          # installs required platform components
   xcodebuild -downloadPlatform iOS    # iOS 26 simulator runtime (~8 GB)
   ```
4. **[C]** Verify: `xcodebuild -version` prints `Xcode 26.x`; `xcrun simctl list runtimes` shows an `iOS 26.x` runtime; `xcrun simctl list devices available` includes an iPhone 17 Pro (the simulator name CLAUDE.md's build command assumes — if the runtime ships different device types, note the actual name now and substitute it consistently).

#### Step 2 — Apple Developer Program + test devices **[H]**
1. Enroll (or confirm) Apple Developer Program membership for the team account (developer.apple.com; $99/yr; can take ~24–48 h). A free personal team *can* sign the Phase-0 device build (7-day profiles) but cannot do TestFlight (Phase 10) — enroll now so it's never the critical path.
2. **Tier A device (required):** iPhone 15 Pro or newer, updated to iOS 26.x, **Apple Intelligence enabled** (Settings → Apple Intelligence & Siri → toggle on; the on-device model then downloads in the background — this can take a while on Wi-Fi + charger, and `SystemLanguageModel` reports `.unavailable(modelNotReady)` until done).
3. **Tier B device (strongly recommended):** any other iOS 26-capable iPhone (e.g. iPhone 12–14) for retrieval-only-path testing per spec §2. If unavailable, Tier B behavior can be partially exercised on the Tier A phone by toggling Apple Intelligence off — but that is not the same as a device-not-eligible tier; plan to borrow one before Phase 8.
4. Pair each device: connect via cable, trust the Mac, enable **Developer Mode** (Settings → Privacy & Security → Developer Mode → restart). **[C verify]** `xcrun devicectl list devices` shows the phone(s) as paired/connected.

#### Step 3 — Create the Xcode project **[H — GUI only]**
Xcode → New Project → iOS App:
- Product Name **EchoMind**, Interface SwiftUI, Language Swift, Storage **SwiftData** (fine to accept the template; Phase 1 replaces the model), Testing System: Swift Testing.
- Save to `~/Documents/mob/EchoMind` → repo root is `~/Documents/mob/EchoMind`, sources under `EchoMind/EchoMind/`.
- Project settings: **iOS Deployment Target 26.0**, Swift Language Version 6.
- **Keep the default synchronized folder groups.** This is the load-bearing decision: from here on, files created on disk inside `EchoMind/EchoMind/` appear in the project automatically, and **nobody — human or Claude — ever edits `project.pbxproj`** (CLAUDE.md hard rule).
- Signing & Capabilities: select the team; Automatically manage signing ON; bundle id `com.ajace.echomind` (or the team's convention). **+ Capability → Background Modes → check "Audio, AirPlay, and Picture in Picture."**
- Info tab (target): add
  - `NSMicrophoneUsageDescription` — "EchoMind records audio only while you run a session, to transcribe it on this iPhone. Audio never leaves your device."
  - `NSSpeechRecognitionUsageDescription` — "EchoMind transcribes your recordings entirely on this iPhone. Nothing is sent to a server."
  (Honest, user-facing copy per spec §4.5. Note: with synchronized groups these live as build-setting-generated Info.plist keys — set them in the target editor, not by hand-writing a plist.)
- **[H]** Build & run the empty template app on the Tier A iPhone once. This proves signing, Developer Mode, and the iOS 26 toolchain end-to-end. First device run triggers "Preparing device for development" — let it finish.

#### Step 4 — Install & authenticate Claude Code **[H, verify C]**
Steps 5–7 are performed by Claude Code, so it must be installed and authenticated before they begin (spec §4 item 7; the audit in 1.1 found it only install*able*, not installed):
1. **[H]** `npm i -g @anthropic-ai/claude-code` (the Node 26.3.0 / npm 11.16.0 from 1.1 satisfy the Node 18+ requirement).
2. **[H]** Run `claude` inside `~/Documents/mob/EchoMind` (the directory exists after Step 3) and complete the interactive authentication — this sign-in is human-only work; by definition no [C] executor exists until it's done.
3. **[C verify]** `claude --version` prints a version and Claude Code starts cleanly in the repo. The gate's "able to read `CLAUDE.md`/`PLAN.md`" check completes after Step 5 puts those files at the repo root.

#### Step 5 — Repo + agent scaffolding **[C]**
All of this is terminal work Claude Code performs and verifies:
1. `git init` in `~/Documents/mob/EchoMind`; default branch `main`.
2. `.gitignore` (Xcode standard):
   ```gitignore
   xcuserdata/
   DerivedData/
   build/
   *.xcuserstate
   .DS_Store
   *.ipa
   *.dSYM.zip
   *.dSYM
   ```
   Do **not** ignore `*.xcodeproj` — the pbxproj is shared state; we just never edit it.
3. Copy `~/Documents/mob/echomind-claude-code-execution-plan.md` → `PLAN.md` at repo root.
4. Write `CLAUDE.md` at repo root **verbatim from PLAN.md §5** (the markdown block there is the file content — no edits, no additions). If Step 1 revealed a different default simulator name than "iPhone 17 Pro", this is the one permitted substitution, per CLAUDE.md's own note.
5. Create `.claude/skills/build-check/SKILL.md` verbatim from PLAN.md §5 (same simulator-name caveat).
6. First commit: `chore(phase-0): empty EchoMind project, CLAUDE.md, PLAN.md, build-check skill`.

#### Step 6 — Folder skeleton for synchronized groups **[C]**
Create the architecture directories inside the app source folder with one minimal Swift placeholder each, so synchronized groups materialize them in Xcode and later phases only *add* files. Placeholders are real Swift (empty non-Swift files like `.gitkeep` inside a synchronized group risk being treated as bundle resources; empty dirs aren't tracked by git at all):

```
EchoMind/EchoMind/
├── EchoMindApp.swift          (template — leave as is)
├── Features/
│   └── Home/
│       ├── HomeView.swift             (placeholder view, used by ContentView for now)
│       └── HomeViewModel.swift        (placeholder)
├── Core/
│   ├── Audio/CoreAudioModule.swift
│   ├── Transcription/CoreTranscriptionModule.swift
│   ├── AI/CoreAIModule.swift
│   ├── RAG/CoreRAGModule.swift
│   └── Storage/CoreStorageModule.swift
└── Models/ModelsModule.swift
```

Placeholder pattern — compiles under Swift 6, zero behavior, deleted when the first real file lands in that folder:

```swift
// Core/Audio/CoreAudioModule.swift
/// Namespace marker for Core/Audio. Replaced by AudioEngineManager in Phase 2.
enum CoreAudioModule {}
```

`Features/Home/HomeView.swift` may be a real (trivial) SwiftUI view so the placeholder tree exercises the View/ViewModel convention:

```swift
// Features/Home/HomeView.swift
import SwiftUI

struct HomeView: View {
    var body: some View {
        Text("EchoMind — Phase 0")
    }
}
```

Do **not** pre-create protocol stubs for `TranscriptionService`, `ModelGateway`, etc. here — those signatures belong to their phases (1, 2, 3, 5, 7) where they're designed against real call sites. Phase 0 pins only the folder contract from CLAUDE.md.

#### Step 7 — Toolchain proof + commit **[C, then H]**
1. **[C]** `xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build` (or the substituted name) — must succeed with zero errors and zero new warnings. This proves: Xcode 26 selected, iOS 26 SDK present, synchronized groups picked up every placeholder.
2. **[C]** `xcodebuild ... test` on the template test target — proves the test toolchain before Phase 1 writes real tests.
3. **[H]** Run once more on the physical Tier A iPhone from Xcode (placeholders included).
4. **[C]** Commit: `chore(phase-0): folder skeleton + placeholders; simulator + device build green`.

### 1.3 Edge cases & failure modes

| Failure | Handling |
|---|---|
| Xcode 26 point release requires macOS 26 while machine is on 15.5 | Caught in Step 1.1. Either install the last 26.x that supports 15.5, or upgrade macOS first. Never build the project against the iOS 18 SDK "temporarily" — nothing in Phases 3+ will compile. |
| xip expansion fails / disk fills mid-install | Root cause is Step 0 skipped. Delete the partial `.app`, clear `~/Library/Caches`, re-check free space, retry. |
| `xcodebuild` still reports 16.4 or CLT after install | `xcode-select -p` was never switched, or a shell alias caches the path. Re-run Step 1.3; verify with `xcrun --show-sdk-version --sdk iphoneos` ≥ 26.0. |
| Simulator runtime download stalls/fails | Re-run `xcodebuild -downloadPlatform iOS`; or Xcode → Settings → Components. Corporate proxies/VPNs are the usual culprit. |
| "Failed to register bundle identifier" on device run | Bundle id collision or free-team cap. Change to a unique reverse-DNS id; confirm the paid team is selected. |
| Developer Mode toggle absent on iPhone | Appears only after Xcode first attempts an install with the device connected. Connect, attempt run, then check Settings → Privacy & Security. |
| Apple Intelligence enabled but model "not ready" for days | Device must be on Wi-Fi, charging, with sufficient storage; the download is opportunistic. Not a Phase 0 blocker (first needed in Phase 5), but start it now. |
| A file added on disk doesn't appear in Xcode | It was created outside `EchoMind/EchoMind/` (outside the synchronized root), or someone converted the group to a manual group. Fix the path; never "fix" it by editing the pbxproj. |
| Template app fails codesign from `xcodebuild` CLI but works in Xcode GUI | Simulator builds need no signing — CLI build per CLAUDE.md targets the simulator, so this indicates a wrong destination string, not a signing problem. Device installs stay a GUI/human step in V1. |

**Testing split for this phase:** there is nothing to unit-test yet; the "tests" are toolchain proofs (Step 7). Be explicit about the simulator's limits from day one: it cannot validate mic capture quality, background/lock-screen audio continuation, Foundation Models availability (`SystemLanguageModel` on simulator does not reflect real Tier A/B behavior), NLContextualEmbedding asset downloads, or real performance/battery. Every later phase's device-verify steps exist because of this; Phase 0's device run only proves signing + launch.

### 1.4 Acceptance gate — Phase 0 commit gate

All boxes checked before Phase 1 starts:

- [ ] ≥ 30 GB free disk *after* all installs (headroom for DerivedData + device support).
- [ ] `xcodebuild -version` → Xcode 26.x; `xcode-select -p` → the 26.x `.app`'s Developer dir; license accepted.
- [ ] `xcrun simctl list runtimes` shows iOS 26.x; the simulator named in CLAUDE.md exists.
- [ ] Apple Developer Program membership active; Tier A iPhone (15 Pro+, iOS 26, Apple Intelligence ON, model download started) paired with Developer Mode enabled; Tier B device sourced or explicitly deferred with a note.
- [ ] Project `EchoMind`: SwiftUI, Swift 6, min iOS 26.0, synchronized folder groups intact (pbxproj untouched since creation).
- [ ] Signing: team set; **Background Modes → Audio** capability present; both usage strings (`NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`) set with the honest copy.
- [ ] Repo: `git init` done; `.gitignore`, `PLAN.md` (spec copy), `CLAUDE.md` (verbatim §5), `.claude/skills/build-check/SKILL.md` committed.
- [ ] Folder skeleton (`Features/Home`, `Core/{Audio,Transcription,AI,RAG,Storage}`, `Models/`) with Swift placeholders, all visible in Xcode's navigator without any pbxproj edit.
- [ ] `/build-check` (simulator build) green; template test target runs.
- [ ] Empty app installed and launched on the physical Tier A iPhone.
- [ ] Claude Code installed (`claude --version`), authenticated, and able to read `CLAUDE.md`/`PLAN.md` from the repo root.
- [ ] Final Phase 0 commit pushed/tagged locally (`phase-0`).

### 1.5 Section risks & mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| ~~**Disk space** (20 GB free vs ≥ 60 GB needed) derails the install mid-xip~~ **RESOLVED 2026-07-06 → 73.9 GB free** (Docker VM disk was the hog, deleted) | ~~High~~ Closed | Was: verify with `df -h` before Step 1, delete the xip after expansion. Monitor going forward: don't let Docker's recreated VM or DerivedData creep back under ~40 GB before/during the install. |
| macOS 15.5 vs newest Xcode 26.x requirement mismatch | Medium | Requirements check is Step 1.1, *before* any download; budget a half-day for a macOS upgrade if needed. |
| Developer Program enrollment latency (24–48 h) blocks device signing | Medium | Kick off enrollment on day one, in parallel with Steps 0–1; free-team signing as a stopgap for the Phase 0 device run only. |
| Apple Intelligence model not downloaded by Phase 5 | Medium | Enable in Step 2 (weeks early), keep the phone on Wi-Fi + charger overnight; Phase 5's Tier detection will surface `.modelNotReady` honestly if it happens anyway. |
| Someone opens the pbxproj "just to add one file" and breaks the synchronized-groups contract | Low | CLAUDE.md hard rule + this gate's "pbxproj untouched" check; if it happens, `git checkout -- EchoMind.xcodeproj` and add the file on disk instead. |
| Simulator device name drift (no "iPhone 17 Pro" in the shipped runtime) | Low | Detected in Step 1.4; substitute once, consistently, in CLAUDE.md and SKILL.md at creation time — never mid-project. |

---

## 2. Phase 1 — Storage Foundation, Navigation, Onboarding & Consent

**Objective.** Ship the app skeleton every later phase builds on: the full V1 SwiftData schema (locked now so we never migrate mid-project), protocol-based repositories, the `AppDependencies` composition root, five-tab navigation, the onboarding/consent flow, and a `PermissionManager` that primes but does not yet trigger system prompts. Exit state = spec Phase 1 acceptance: clean build, onboarding shows exactly once, tabs navigate, debug dummy-session round-trip works.

**Why the whole schema now:** Phases 3–8 all write into these tables. SwiftData migrations are the single most expensive rework in this project, so we define all six models in Phase 1 — even the ones (KnowledgeChunk, ChatMessage) with no UI until Phases 7–8 — and freeze them behind a `VersionedSchema`.

### 2.1 Work breakdown — files to create

All paths are inside the synchronized folder group; Claude Code creates files only, never touches the `.xcodeproj`.

| File | Purpose |
|---|---|
| `App/EchoMindApp.swift` | (exists from template — edit) builds `AppDependencies`, injects container + dependencies |
| `App/RootView.swift` | switches onboarding vs. `MainTabView` on the persisted flag |
| `App/AppDependencies.swift` | composition root — the only allowed singleton-ish object |
| `Core/Storage/Session.swift` · `TranscriptSegment.swift` · `Document.swift` · `KnowledgeChunk.swift` · `ChatMessage.swift` · `AppSettings.swift` | the six `@Model` classes (spec §8) |
| `Core/Storage/SchemaV1.swift` | `VersionedSchema` enumerating all six models |
| `Core/Storage/ModelContainerFactory.swift` | live/in-memory containers + file-protection application |
| `Core/Storage/SessionRepository.swift` · `DocumentRepository.swift` · `ChunkRepository.swift` | repository protocols |
| `Core/Storage/SwiftDataSessionRepository.swift` · `SwiftDataDocumentRepository.swift` · `SwiftDataChunkRepository.swift` | `@ModelActor` implementations |
| `Core/Storage/AppSettingsStore.swift` | fetch-or-create single-row `AppSettings` accessor (`@MainActor`) |
| `Core/Permissions/PermissionManager.swift` | protocol + live implementation (new `Core/Permissions` folder; used by both Audio and Transcription later) |
| `Models/SourceType.swift` · `DocumentStatus.swift` · `MessageRole.swift` · `SourceRef.swift` · `PermissionState.swift` | pure value types shared across layers |
| `Models/Snapshots.swift` | `SessionSnapshot`, `SegmentSnapshot`, `DocumentSnapshot`, `ChunkSnapshot` value types returned by repositories |
| `Features/Onboarding/View/OnboardingView.swift` (+ `WelcomeStepView.swift`, `PrivacyStepView.swift`, `ConsentStepView.swift`, `PermissionPrimingStepView.swift`) | four-step onboarding pager |
| `Features/Onboarding/ViewModel/OnboardingViewModel.swift` | step state machine + persistence |
| `Features/Home/View/HomeView.swift` · `Features/Sessions/View/SessionsView.swift` · `Features/Knowledge/View/KnowledgeView.swift` · `Features/Ask/View/AskView.swift` · `Features/Settings/View/SettingsView.swift` | tab placeholders (real navigation, stub content) |
| `Features/Settings/View/DebugStorageSection.swift` | `#if DEBUG` dummy-session smoke test |
| `EchoMindTests/StorageTests.swift` · `OnboardingTests.swift` · `PermissionManagerTests.swift` | unit tests (in-memory container, mocks) |

### 2.2 SwiftData models (spec §8 — authoritative field list)

Design rules applied to all six:

- **Enums stored as raw `String`** (`sourceTypeRaw`, `statusRaw`, `roleRaw`) with typed computed accessors — `#Predicate` works reliably on primitives, not on custom enum cases.
- **Timestamps** are `TimeInterval` offsets from session start (`startTime`/`endTime`); wall-clock fields are `Date`.
- **No CloudKit.** Never add the iCloud entitlement; `ModelConfiguration(cloudKitDatabase: .none)` stays explicit so nobody "helpfully" syncs private transcripts.

```swift
@Model final class Session {
    #Index<Session>([\.createdAt])
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var duration: TimeInterval
    var summaryJSON: String?          // JSON-encoded MeetingSummary, written in Phase 5
    var sourceTypeRaw: String         // SourceType: live | import
    var tags: [String]
    @Relationship(deleteRule: .cascade, inverse: \TranscriptSegment.session)
    var segments: [TranscriptSegment] = []
}

@Model final class TranscriptSegment {
    @Attribute(.unique) var id: UUID
    var text: String
    var startTime: TimeInterval       // offset from session start
    var endTime: TimeInterval
    var speakerLabel: String?
    var createdAt: Date
    var session: Session?             // inverse of Session.segments
}

@Model final class KnowledgeChunk {
    #Index<KnowledgeChunk>([\.sourceId])
    @Attribute(.unique) var id: UUID
    var sourceId: UUID                // polymorphic: Session.id or Document.id
    var sourceTypeRaw: String         // SourceType: document | session
    var text: String
    var embedding: Data               // packed little-endian [Float]; inline, NOT .externalStorage
    var chunkIndex: Int
    var pageNumber: Int?
    var timestamp: TimeInterval?
    var createdAt: Date
}
```

`Document` (`id`, `title`, `fileName`, `fileTypeRaw`, `textContent`, `pageCount?`, `pageBreaks: [Int]`, `statusRaw`, `createdAt`) marks `textContent` with `@Attribute(.externalStorage)` — extracted PDF text can approach the 5 MB cap (spec Phase 6) and doesn't belong in row storage. `pageBreaks` is the Phase 7 plan's first amendment to spec §8 (rag.md §6.2): the UTF-16 offset into `textContent` at which each page starts (element *i* is the start of page *i + 1*; page 1 starts at offset 0). Phase 6's PDF extraction writes it at import time (empty `[]` until then, and for non-paginated documents); it's what lets Phase 7 re-index and rebuild page-numbered chunks from the stored `Document` alone, since the original PDF is never kept. `ChatMessage` (`id`, `conversationId`, `roleRaw`, `content`, `sourceRefsData: Data`, `createdAt`) stores `sourceRefs` as JSON-encoded `[SourceRef]` behind a computed property — deterministic bytes, migration-safe, and we never query inside it. `AppSettings` (`onboardingComplete`, `consentAcknowledged`, `preferredLocale?`, `lastIndexRebuild?`, `embeddingDimension: Int?`) is a single-row table accessed only through `AppSettingsStore.fetchOrCreate()` on `@MainActor` (serializes access; prevents duplicate rows). `embeddingDimension` is the second §6.2 amendment: nil until Phase 7's first index run records the OS embedding model's dimension; a mismatch on a later load signals the model changed and forces a rebuild prompt. Both amendment fields are declared **now**, in `SchemaV1`, precisely because rag.md says "declare the field in Phase 1 if building from this plan" — omitting them would force the mid-project migration this phase exists to prevent (rag.md's Phase 7 files-to-modify list would otherwise have to edit the frozen `Core/Storage` model files).

**Decisions worth writing down:**

- **Transcript is derived, never stored twice.** `Session` has no `transcript` field; the full transcript is always `segments.sorted(by: startTime).map(\.text).joined()`. Rationale: Phase 3 persists segments incrementally while recording (crash-safety requirement), so a duplicate transcript column would be perpetually stale or force a rewrite of a growing blob on every segment — and two copies *will* drift. Search (Phase 4), export (Phase 4), chunking (Phase 7) all consume segments.
- **Embedding as packed `[Float]` in `Data`.** SwiftData would encode a `[Float]` property via Codable (bloated plist encoding). Packed raw bytes are 4 bytes/dimension exactly and unpack with one `withUnsafeBytes` copy straight into the `vDSP` dot-product path (Phase 7). Kept **inline** (no `.externalStorage`): ~2–3 KB per vector, and brute-force search must bulk-load thousands of them fast — one row fetch each, not one file open each. The pack/unpack utilities ship in Phase 7; only the `Data` type is fixed now.
- **Segments cascade at the DB level; chunks cannot.** `KnowledgeChunk.sourceId` is polymorphic (session *or* document), so no SwiftData relationship is possible. Cascade is enforced in repositories instead: `SwiftDataSessionRepository.delete` and `...DocumentRepository.delete` must delete matching chunks in the same transaction. A unit test asserts zero orphan chunks after each delete — this is the regression guard for spec Phase 4's "no orphaned segments or chunks."

### 2.3 ModelContainer + file protection `.completeUnlessOpen`

**Why:** Phase 2/3 keep recording and persisting finalized segments while the phone is locked. iOS's default (`completeUntilFirstUserAuthentication`) would work but under-protects; `.complete` would break background writes the moment the device locks. `.completeUnlessOpen` is the correct middle: files already open stay writable after lock, and new files can still be created — exactly the locked-phone recording scenario — while everything is sealed once closed.

Two layers, both applied:

1. **Entitlement (human):** in Xcode → Signing & Capabilities → add **Data Protection**, then edit the `.entitlements` value `com.apple.developer.default-data-protection` to `NSFileProtectionCompleteUnlessOpen` (Xcode's toggle defaults to `...Complete`). This sets the default for every file the app creates.
2. **Programmatic (Claude Code):** `ModelContainerFactory.live()` uses an explicit `ModelConfiguration` URL in Application Support, then applies `FileManager` attributes `[.protectionKey: FileProtectionType.completeUnlessOpen]` to the store file **and its `-wal` / `-shm` sidecars** (SQLite WAL files are where locked-phone writes actually land; missing them is the classic bug).

```swift
enum ModelContainerFactory {
    static func live() throws -> ModelContainer      // on-disk, protected, cloudKitDatabase: .none
    static func inMemory() throws -> ModelContainer  // isStoredInMemoryOnly: true — tests & previews
}
```

If `live()` throws (disk full, corrupt store), the app shows a blocking "storage unavailable" screen with the error — never `fatalError` in release.

### 2.4 Repositories — protocols only above the storage layer

`@Model` classes are **not Sendable and never leak past `Core/Storage`**. Repositories exchange `Sendable` snapshot structs from `Models/` (this is what the CLAUDE.md split "Core/Storage = SwiftData models" vs. "Models/ = pure data types" is for). Implementations are `@ModelActor` actors from day one so Phase 3's incremental segment writes and Phase 7's bulk indexing get off-main persistence with zero call-site changes.

```swift
protocol SessionRepository: Sendable {
    func create(_ snapshot: SessionSnapshot) async throws
    func appendSegment(_ segment: SegmentSnapshot, toSession id: UUID) async throws // Phase 3 uses this
    func update(_ snapshot: SessionSnapshot) async throws
    func fetchAll() async throws -> [SessionSnapshot]          // sorted by createdAt desc
    func fetchSession(id: UUID) async throws -> SessionSnapshot?
    func fetchSegments(sessionId: UUID) async throws -> [SegmentSnapshot]
    func delete(id: UUID) async throws                          // cascades segments + sweeps chunks
}

protocol DocumentRepository: Sendable { /* create/fetchAll/updateStatus/delete(id:) — delete sweeps chunks */ }

protocol ChunkRepository: Sendable {
    func insert(_ chunks: [ChunkSnapshot]) async throws         // batched, one save per batch
    func fetchAll() async throws -> [ChunkSnapshot]             // Phase 7 vector scan
    func deleteChunks(sourceId: UUID) async throws
    func deleteAll() async throws                               // "Rebuild index", Phase 7/9
}
```

Implementations save explicitly (`try context.save()`) after each mutation — no reliance on autosave, which makes crash-loss behavior predictable for Phase 3. View models depend on the protocol types only; nothing outside `Core/Storage` imports SwiftData except the `App/` wiring.

### 2.5 AppDependencies composition root

The **only allowed singleton** (per CLAUDE.md). Built once in `EchoMindApp.init`, injected via SwiftUI environment; every later service (AudioEngineManager, TranscriptionService, ModelGateway, EmbeddingService…) is added here in its phase.

```swift
@MainActor @Observable
final class AppDependencies {
    let sessionRepository: any SessionRepository
    let documentRepository: any DocumentRepository
    let chunkRepository: any ChunkRepository
    let permissions: any PermissionManaging
    let settingsStore: AppSettingsStore

    static func live() throws -> AppDependencies      // real container + services
    static func preview() -> AppDependencies          // in-memory container + seeded data + stub permissions
}
```

Usage: `.environment(dependencies)` at the root, `@Environment(AppDependencies.self)` in views; view models receive the specific protocols they need through their initializers (constructor injection), never the whole bag. Previews and unit tests call `.preview()` / hand-rolled mocks — this is the swap mechanism, and it is why every service is a protocol.

### 2.6 Tab navigation

`MainTabView`: SwiftUI `TabView` with five tabs — Home, Sessions, Knowledge, Ask, Settings — each wrapping its placeholder view in its own `NavigationStack` (independent per-tab navigation state, needed by Phase 4+). Placeholders show the tab name and an SF Symbol; Settings additionally hosts `DebugStorageSection`. No business logic here; the point is that every later phase lands its feature into an existing slot.

### 2.7 Onboarding & consent flow

`OnboardingViewModel` drives an explicit state machine — `enum Step { welcome, privacy, consent, permissionPriming }` — rendered by `OnboardingView` as a non-swipeable pager (forward via buttons only, so consent can't be skipped by swiping).

1. **Welcome** — app value proposition, one screen.
2. **Privacy explainer** — "everything stays on this iPhone": no accounts, no cloud, no network. Plain copy.
3. **Recording-consent notice** — plain-language (not legalese) statement that the user is responsible for informing participants before recording, and that laws vary by location. Continue button is explicit acknowledgment ("I understand") → sets `consentAcknowledged = true`. This copy is reused verbatim in Settings (Phase 9) — put the string in one shared constant.
4. **Permission priming** — explains *why* mic and speech permissions will be requested, with "You'll be asked when you start your first recording." **No system prompt fires here** — deferring to the moment of first recording (Phase 3) maximizes grant rate and keeps a denied-at-onboarding state from bricking the flow.

Persistence: `onboardingComplete = true` is written **only** when the last step finishes; killing the app mid-flow restarts onboarding from the welcome screen (acceptable, deliberate). `RootView` reads `AppSettings` synchronously via `AppSettingsStore` on the main context at launch — single-row fetch, no async flash-of-wrong-screen.

### 2.8 PermissionManager

```swift
enum PermissionState: Sendable { case notDetermined, granted, denied }

protocol PermissionManaging: Sendable {
    func microphoneState() -> PermissionState
    func speechState() -> PermissionState
    func requestMicrophone() async -> PermissionState   // AVAudioApplication.requestRecordPermission()
    func requestSpeech() async -> PermissionState       // SFSpeechRecognizer.requestAuthorization
}
```

Live implementation maps `AVAudioApplication.shared.recordPermission` and `SFSpeechRecognizer.authorizationStatus()` into `PermissionState` (`.undetermined → .notDetermined`; `.denied`/`.restricted → .denied`). **Note the deliberate exception to the "no SFSpeechRecognizer" rule:** it is used *only* for the authorization API — SpeechTranscriber rides the same speech-recognition authorization, and there is no SpeechAnalyzer-native request call. No transcription path may ever touch `SFSpeechRecognizer` beyond these two symbols; say so in a code comment. `request*` methods exist and are tested via a mock now, but are first *called* in Phase 3. Requires the two Info.plist usage strings from spec §4 (human, already done).

### 2.9 Debug storage smoke test

`DebugStorageSection` (compiled `#if DEBUG` only, in Settings): three buttons — **Insert dummy session** (a `Session` + 3 `TranscriptSegment`s through `SessionRepository`), **Fetch counts** (shows sessions/segments/chunks counts), **Delete dummy** (verifies cascade → segment count returns to baseline). This is the end-to-end proof that container, actor-isolated repository, and cascade rules work in the running app, not just in tests.

### 2.10 Ordered build steps

| # | Step | Who |
|---|---|---|
| 0 | Spec §4 prerequisites done; **add Data Protection capability and set entitlement value to `NSFileProtectionCompleteUnlessOpen`**; confirm a unit-test target exists (adding targets edits the pbxproj → human-only, one time) | Human |
| 1 | `Models/` value types + six `@Model` classes + `SchemaV1` + `ModelContainerFactory`; unit tests on the in-memory container (cascade, unique ids, AppSettings fetch-or-create) | Claude Code |
| 2 | Repository protocols + `@ModelActor` implementations + orphan-chunk sweep tests | Claude Code |
| 3 | `AppSettingsStore` + onboarding flow (`OnboardingView`, step views, `OnboardingViewModel`) + state-machine tests | Claude Code |
| 4 | `PermissionManager` (protocol + live implementation) + mock + mapping tests | Claude Code |
| 5 | `AppDependencies` (+ `.preview()`), app wiring, `RootView`, `MainTabView` + five placeholders | Claude Code |
| 6 | `DebugStorageSection`; full `xcodebuild` build + test pass | Claude Code |
| 7 | Device verification (below) + commit `feat(phase-1): storage, navigation, onboarding + consent` | Human |

Order rationale: schema first because everything depends on it and it's the migration risk; repositories before UI so the smoke test exercises the real stack; `AppSettingsStore`/onboarding and `PermissionManager` before the composition root because `AppDependencies` declares `permissions: any PermissionManaging` and `settingsStore: AppSettingsStore` (§2.5) and `RootView` reads the onboarding flag via `AppSettingsStore` to switch to `OnboardingView` (§2.7) — wiring last means every step compiles and passes the "always build after changes" rule with no stubs or improvised reordering.

### 2.11 Edge cases & failure modes

- **Kill mid-onboarding** → onboarding restarts from step 1 (flag written only at the end). Test it.
- **`ModelContainer` creation failure** (disk full / corrupt store) → blocking error screen, no crash; never silently fall back to in-memory in release.
- **Duplicate `AppSettings` rows** → impossible by construction (single `@MainActor` fetch-or-create path); test idempotence under repeated calls.
- **WAL sidecars missing protection attributes** → apply attributes after container creation *and* rely on the entitlement default; log resulting attributes in DEBUG.
- **Permission state changed in iOS Settings while app backgrounded** → `PermissionManager` reads live status on demand (no cached state), so Phase 3 always sees truth.
- **`@Model` escaping the storage layer** → compile-time discipline: only `Core/Storage` + `App/` import SwiftData; reviewer greps for `import SwiftData` elsewhere at the commit gate.

### 2.12 Unit tests vs. device verification

**Unit tests (simulator, in-memory container):** cascade delete session→segments; repository chunk sweep on session/document delete; AppSettings fetch-or-create idempotence; snapshot round-trip (model→snapshot→model); onboarding state machine (ordering, flag written only at completion); PermissionManager status mapping via mocked authorizers.

**Device-only verification (simulator cannot validate):** file-protection behavior under an actual passcode lock (attributes are inert in the simulator — full locked-write validation lands with Phase 2/3 recording tests, but verify the attributes are *set* now via the DEBUG log on device); fresh-install onboarding + relaunch-skip on a real iPhone; real permission strings rendering in the priming screens. Mic capture quality, background audio, and Foundation Models availability are also device-only — irrelevant this phase but the reason Phase 1 must not claim to validate them.

### 2.13 Acceptance gate — commit checklist

- [ ] `xcodebuild … build` and `… test` pass clean; zero new warnings
- [ ] All six models compile under `SchemaV1`; store opens on device; protection attributes logged as `completeUnlessOpen` (store + `-wal` + `-shm`)
- [ ] Fresh install shows onboarding exactly once; force-quit mid-flow re-shows it; completion persists across relaunch
- [ ] Consent step requires explicit acknowledgment; `consentAcknowledged` persisted
- [ ] **No system permission dialog appears anywhere in Phase 1**
- [ ] All five tabs navigate; each is its own `NavigationStack`
- [ ] Debug insert → fetch → cascade-delete round-trip works in-app; orphan-chunk test green
- [ ] `grep -rE 'URLSession|Network\b' EchoMind/` → no hits; `import SwiftData` only in `Core/Storage` + `App/`
- [ ] Committed as `feat(phase-1): …`; `/clear` before Phase 2

### 2.14 Phase risks & mitigations

| Risk | Mitigation |
|---|---|
| Schema change needed in a later phase → SwiftData migration mid-project | Whole V1 schema (spec §8) locked now inside a `VersionedSchema`; later changes must be additive and reviewed against §8 |
| File protection silently wrong (entitlement default vs. WAL sidecars) | Dual approach (entitlement + programmatic attributes incl. sidecars) + DEBUG attribute logging + explicit locked-recording test in Phase 2 |
| `@Model` non-Sendability causes concurrency warnings/rework in Phases 3/7 | Snapshot-struct boundary + `@ModelActor` repositories from day one; Swift 6 strict concurrency surfaces violations at compile time |
| Polymorphic `sourceId` leaves orphan chunks after deletes | Repository-enforced sweep + dedicated unit test (the DB cannot enforce this) |
| Onboarding flag written too early → users trapped past consent | Flag written only on final step; force-quit test in the gate |
| Test target absent (template choice) blocks all unit testing | Explicit human step 0 — Claude Code must not add targets (pbxproj is off-limits) |

---

## 3. Phases 2–3 — Audio Engine, Background Recording & Live Transcription

This is the schedule-risk center of V1 (PLAN.md §11). Phases 2 and 3 are built as **one pipeline** — `AudioEngineManager → BufferConverter → SpeechAnalyzerTranscriber → LiveTranscriptViewModel → SwiftData` — but committed as two gates. Everything here presumes Phase 1 landed: SwiftData store with `.completeUnlessOpen` file protection (so writes continue while locked), `PermissionManager`, and the onboarding consent flow. Human prerequisite from PLAN.md §4/§7: **Background Modes → Audio** enabled and both usage strings present *before* Phase 2 starts — Claude Code cannot edit capabilities or the pbxproj.

### 3.1 Work breakdown — files to create

| File | Purpose |
|---|---|
| `Models/RecordingState.swift` | `RecordingState` enum + `AudioEngineEvent` (pure, Sendable) |
| `Models/TranscriptionUpdate.swift` | Update struct: text, isFinal, audio time range |
| `Models/AudioCaptureError.swift` | Typed errors for capture path |
| `Models/TranscriptionError.swift` | Typed errors for speech path (incl. asset/locale cases) |
| `Core/Audio/AudioSessionConfigurator.swift` | Protocol + impl wrapping AVAudioSession category/activation |
| `Core/Audio/AudioInterruptionStateMachine.swift` | **Pure** state machine: notification payloads → commands |
| `Core/Audio/AudioEngineManager.swift` | Actor owning AVAudioEngine; tap → buffer stream; event stream |
| `Core/Audio/AudioLevelMeter.swift` | RMS/peak from PCM buffers (vDSP), for the UI level state |
| `Core/Transcription/TranscriptionService.swift` | Protocol (see §3.3) |
| `Core/Transcription/SpeechAssetManager.swift` | Locale support check + AssetInventory download w/ progress |
| `Core/Transcription/BufferConverter.swift` | AVAudioConverter: tap format → analyzer's required format |
| `Core/Transcription/SpeechAnalyzerTranscriber.swift` | SpeechAnalyzer + SpeechTranscriber implementation |
| `Features/LiveTranscript/LiveTranscriptViewModel.swift` | @MainActor orchestration + incremental persistence |
| `Features/LiveTranscript/LiveTranscriptView.swift` | Start/Stop, transcript, auto-scroll, error surfaces |
| `Features/LiveTranscript/RecordingIndicatorView.swift` | Red dot + elapsed timer component (reused later) |
| `Features/LiveTranscript/DebugSegmentInspectorView.swift` | **DEBUG-only** overlay: live count + last few persisted `TranscriptSegment`s for the active session (verification tooling for §3.8) |
| `EchoMindTests/AudioInterruptionStateMachineTests.swift` | Synthetic-notification matrix tests |
| `EchoMindTests/BufferConverterTests.swift` | Format-conversion round-trips on synthesized buffers |
| `EchoMindTests/LiveTranscriptViewModelTests.swift` | Mock service streams → VM state + persistence |
| `EchoMindTests/IncrementalPersistenceTests.swift` | In-memory ModelContainer; finalized-segment writes |

All files stay under ~300 lines (CLAUDE.md rule); new files land in existing synchronized folders — never touch the project file.

### 3.2 Audio engine (Phase 2)

**Session configuration** (in `AudioSessionConfigurator`, one place only): category `.playAndRecord`, mode `.default`, options `[.allowBluetoothHFP, .duckOthers]`. Rationale: `.playAndRecord` tolerates route changes better than `.record` and leaves room for playback cues later; `.allowBluetoothHFP` is required for AirPods *microphone* input; avoid `.measurement` mode (disables input processing that helps speech). Activate on `start()`, deactivate with `.notifyOthersOnDeactivation` on `stop()`. This is a device-verifiable decision — if AirPods input misbehaves, the configurator is the single file to adjust.

```swift
// Core/Audio/AudioEngineManager.swift
protocol AudioCapturing: Actor {
    /// UI-facing events: state changes, audio level, elapsed time, input-format changes.
    nonisolated var events: AsyncStream<AudioEngineEvent> { get }
    /// Starts session + engine + input tap. One capture at a time.
    func start() async throws -> AsyncThrowingStream<AVAudioPCMBuffer, Error>
    /// Idempotent. Finishes the buffer stream, deactivates the session.
    func stop() async
}

enum AudioEngineEvent: Sendable {
    case stateChanged(RecordingState)          // idle / recording / pausedByInterruption
    case level(Float)                           // 0…1, throttled to ~10 Hz
    case elapsed(TimeInterval)                  // accumulated ACTIVE capture seconds, ~1 Hz; frozen while paused
    case inputFormatChanged(sampleRate: Double, channels: UInt32)
}
```

Implementation notes that pin the design:
- The input tap installs on `inputNode` with `inputNode.outputFormat(forBus: 0)` — **never a hardcoded format**. The tap block is synchronous and audio-thread-hot: it may only `continuation.yield(buffer)` and feed `AudioLevelMeter`; no allocation-heavy work, no actor hops.
- The buffer stream uses `.unbounded` buffering. Consumption (analyzer) is faster than production; memory stays flat because buffers are consumed within milliseconds — assert this in the device soak test.
- Elapsed time counts **active capture only**: it pauses during interruptions (a 10-minute call must not inflate a 2-minute recording). The manager tracks accumulated time across pause/resume and publishes it as `elapsed(TimeInterval)` events on the `events` stream (~1 Hz while recording, frozen while paused) — this is the spec's "published elapsed-time/level state for UI"; the ViewModel only renders the latest value, it never keeps its own clock.
- No always-listening: the engine and session exist only between explicit `start()`/`stop()`. Nothing arms audio at app launch.

**Interruption and route-change matrix** — implemented as a *pure* state machine so the whole matrix is unit-testable without hardware:

```swift
// Core/Audio/AudioInterruptionStateMachine.swift
enum AudioSessionEvent: Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeChanged(reason: AVAudioSession.RouteChangeReason)
    case mediaServicesReset
}
enum AudioCommand: Sendable {
    case pauseCapture, resumeCapture, reinstallTap, rebuildEngine, surfacePausedState
}
struct AudioInterruptionStateMachine {
    mutating func handle(_ event: AudioSessionEvent, while state: RecordingState) -> [AudioCommand]
}
```

| Trigger | Behavior |
|---|---|
| Interruption **began** (call, Siri) | `pauseCapture` (engine pause, keep tap + session objects), state → `.pausedByInterruption`, timer frozen, UI shows "Paused — on a call" |
| Interruption **ended, shouldResume** | Reactivate session, `resumeCapture`, state → `.recording`. If reactivation throws, retry once after 0.5 s, then surface a resumable error |
| Interruption **ended, no resume flag** | Stay paused; show explicit "Resume" button — never silently lose the rest of a meeting |
| **Route change** (`.newDeviceAvailable` / `.oldDeviceUnavailable`, AirPods in/out) | Keep recording. Remove and reinstall the tap with the **new** `inputNode.outputFormat(forBus: 0)` — sample rate/channel count can change (e.g., 48 kHz built-in → 16/24 kHz Bluetooth HFP) — and emit `inputFormatChanged` so `BufferConverter` rebuilds |
| **Media services reset** | Full teardown: discard engine, create a new `AVAudioEngine`, reconfigure session, reinstall tap, resume both streams; log it; brief "recording resumed" toast |

The `AudioEngineManager` subscribes to the three `AVAudioSession` notifications, translates userInfo into `AudioSessionEvent`, and executes returned commands. **Unit-testable:** the entire event→command matrix with synthetic payloads. **Device-only:** whether iOS actually delivers `shouldResume` after a call, real AirPods behavior, and reactivation timing.

**Background continuation — exact guarantees.** Background Modes → Audio keeps the process running *only while the audio session is active and the engine is doing I/O*. It does not: allow starting capture from the background, survive force-quit, or protect against jetsam under extreme memory pressure (mitigated by incremental persistence, §3.4). Locking the screen is just backgrounding; capture, transcription, and SwiftData writes (`.completeUnlessOpen`) all continue. If capture is stopped while backgrounded, the app suspends normally — correct behavior.

### 3.3 Speech pipeline (Phase 3)

```swift
// Core/Transcription/TranscriptionService.swift
protocol TranscriptionService: Sendable {
    /// Consumes the engine's buffer stream; emits volatile + finalized updates.
    func start(
        locale: Locale,
        audio: AsyncThrowingStream<AVAudioPCMBuffer, Error>
    ) async throws -> AsyncThrowingStream<TranscriptionUpdate, Error>
    /// Finalizes pending audio (flushes the volatile tail as final) then finishes the stream.
    func stop() async
}

// Models/TranscriptionUpdate.swift
struct TranscriptionUpdate: Sendable, Equatable {
    let text: String
    let isFinal: Bool                       // false = volatile, will be superseded
    let audioRange: ClosedRange<TimeInterval>  // seconds from session start
}

// Core/Transcription/SpeechAssetManager.swift
enum SpeechAssetStatus: Sendable { case installed, needsDownload, unsupportedLocale }
protocol SpeechAssetManaging: Sendable {
    func status(for locale: Locale) async throws -> SpeechAssetStatus
    func ensureInstalled(for locale: Locale) -> AsyncThrowingStream<Double, Error> // progress 0…1
}
```

**Intentional amendment to the spec's pinned protocol.** PLAN.md's Phase 3 prompt pins `start(locale:) -> AsyncThrowingStream<TranscriptionUpdate>; stop()`. This section deliberately amends that to `start(locale:audio:)`, taking the engine's buffer stream as an explicit parameter instead of having the transcriber reach into `AudioEngineManager` itself. Rationale: it keeps Core/Transcription free of any audio dependency and makes the service fully testable with synthetic buffer streams (§3.8). The amended signature is **authoritative** — every call site in this plan (`LiveTranscriptViewModel`, §3.5) uses it, and no other plan section pins the old shape (Phase 0/bootstrap explicitly defers `TranscriptionService` stubs to this phase). If you are implementing from PLAN.md's verbatim prompt text, use this section's signature.

`SpeechAnalyzerTranscriber` implementation decisions:
- Query `SpeechTranscriber.supportedLocales`; unsupported → `TranscriptionError.localeUnsupported` before any UI shows a Start button as enabled.
- Asset install via `AssetInventory` **must** show progress (PLAN.md test #12). Gate: entering LiveTranscriptView checks status; `needsDownload` renders a progress card before Start is enabled. Download requires network permission by the OS itself, not our code — this remains zero-network *app* code; document it in the Phase 9 audit allowlist rationale (OS-managed asset download, not URLSession in our target).
- **Format bridge:** ask the transcriber/analyzer for its best available audio format; `BufferConverter` wraps `AVAudioConverter` from the tap format to that format. The converter is *format-pair specific* — on `inputFormatChanged` it is discarded and rebuilt. This isolates route-change churn from the analyzer, which sees one continuous, constant-format stream.
- Volatile results stream continuously (target: first partial < ~1 s); finalized results carry authoritative text + audio time ranges. Map finalized ranges to `TranscriptSegment.startTime/endTime`.
- `stop()` must **finalize through end of input** before finishing the stream, so the last utterance is persisted, not dropped as volatile.

### 3.4 Incremental persistence

Owned by `LiveTranscriptViewModel` (via `SessionRepository`), not by the transcriber — keeps Core/Transcription storage-free:
1. On Start (after permissions/assets pass): insert `Session` (sourceType `.live`, placeholder title) and save immediately. The session exists before the first word.
2. On every `isFinal == true` update: insert one `TranscriptSegment` (sessionId, text, startTime, endTime) and **save the context immediately**. Finalized segments arrive every few seconds — write rate is trivial, and force-quit/jetsam loses at most the current volatile tail (the spec's exact durability bar).
3. Volatile text is **never** persisted; only the latest volatile string is kept in memory (no accumulation).
4. On Stop: set `duration` (accumulated active time), default title `"Meeting <date, time>"`, `updatedAt`; final save. On mid-session transcriber failure: same finalize path — the user keeps everything transcribed so far, with an error banner, not a data loss.

### 3.5 Live UI

```swift
// Features/LiveTranscript/LiveTranscriptViewModel.swift
@MainActor @Observable final class LiveTranscriptViewModel {
    enum Phase: Equatable {
        case idle, preparingAssets(progress: Double), recording,
             pausedByInterruption, stopping, failed(TranscriptionError)
    }
    private(set) var phase: Phase = .idle
    private(set) var finalizedLines: [TranscriptLine]  // mirrors persisted segments
    private(set) var volatileText: String = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var level: Float = 0
    func startTapped() async   // permissions → assets → Session insert → start pipeline
    func stopTapped() async
    func scenePhaseChanged(_ new: ScenePhase)
}
```

- Dependencies (`AudioCapturing`, `TranscriptionService`, `SpeechAssetManaging`, `SessionRepository`, `PermissionManager`) injected as protocols from `AppDependencies`. `elapsed` and `level` are pure mirrors of the manager's `AudioEngineEvent.elapsed`/`.level` events (§3.2) — the VM holds no timer of its own.
- `LiveTranscriptView`: Start/Stop button, `RecordingIndicatorView` (red dot pulsing + timer — this is also the consent-visibility requirement from §0.6), finalized text in `.primary`, volatile appended in `.secondary`, `ScrollViewReader` auto-scroll pinned to bottom unless the user has scrolled up (track a `isPinnedToBottom` flag).
- **Unlock catch-up:** while locked, the VM task keeps consuming updates, so state is already current; SwiftUI simply wasn't rendering. On `scenePhaseChanged(.active)`, re-assert scroll-to-bottom. No replay machinery needed — verify on device that memory stayed flat during a locked stretch.
- Permission prompts fire on first Start tap (Phase 1 deferred-priming design), with distinct denied states below.

### 3.6 Error states (all user-readable, all recoverable in place)

| Failure | Detection | UX |
|---|---|---|
| Mic permission denied | `PermissionManager` before start | Inline explainer + "Open Settings" deep link |
| Speech permission denied | `PermissionManager` before start | Same pattern, speech-specific copy |
| Locale unsupported | `SpeechAssetManager.status` | Start disabled; "English (US) transcription isn't available for <locale>" + locale picker hint (AppSettings.preferredLocale) |
| Asset download failed | Thrown by `ensureInstalled` progress stream | Retry button; keep Start disabled; note that download needs the OS to fetch a model once |
| Transcriber fails mid-session | Buffer/update stream throws | Stop audio cleanly, run the Stop finalize path (session kept), error banner "Transcription stopped — your recording up to this point is saved" |
| Session activation fails on resume | Thrown from reactivation | One auto-retry, then paused state with manual Resume |

### 3.7 Ordered build steps

1. **Human:** confirm Background Modes → Audio + both usage strings; clean device build (PLAN.md §4). *Blocked otherwise.*
2. **Claude Code (Phase 2, session 1):** `Models/` types → `AudioSessionConfigurator` → `AudioInterruptionStateMachine` **with its tests first** (pure logic, fastest feedback) → `AudioEngineManager` + `AudioLevelMeter` → `RecordingIndicatorView` + a debug-only harness screen that starts capture and shows level/elapsed. `/build-check` green.
3. **Human:** device smoke test — start/stop repeatedly, level meter moves, lock for 2+ minutes, self-call. **Commit Phase 2** (`feat(phase-2): audio engine + background recording`).
4. **Claude Code (Phase 3, session 2):** `SpeechAssetManager` → `BufferConverter` (+ tests on synthesized sine buffers) → `SpeechAnalyzerTranscriber` → `LiveTranscriptViewModel` (+ mock-driven tests, in-memory SwiftData persistence tests) → `LiveTranscriptView`, replacing the debug harness → `DebugSegmentInspectorView` (DEBUG builds only: fetches the persisted segment count/tail for the active session live, so mid-recording persistence is observable on device). `/build-check` green.
5. **Human:** full device protocol (§3.8), including a **fresh device / deleted-assets** run for download-progress UX. **Commit Phase 3** (`feat(phase-3): live transcription`).

Order rationale: the pure state machine and converter are the only parts with cheap, deterministic feedback — build and test them before anything touching hardware; the debug harness lets the human validate Phase 2 on device *before* speech complexity stacks on top.

### 3.8 Test split — be explicit about what the simulator cannot prove

**Unit tests (simulator/CI-safe):** interruption matrix (synthetic `AVAudioSession` userInfo payloads); BufferConverter format pairs incl. 48 kHz→analyzer and 16 kHz (HFP-like)→analyzer; VM state transitions and incremental persistence via mock `TranscriptionService` streams (in-memory `ModelContainer`); elapsed-time freeze during pause; volatile-replacement rendering logic; stop-path finalization on a throwing stream.

**Device-only — the simulator cannot validate:** real mic capture quality and levels, background/locked continuation, genuine call/Siri interruptions and `shouldResume` delivery, Bluetooth route changes and HFP sample-rate shifts, AssetInventory download behavior, SpeechTranscriber accuracy/latency, memory/battery under load. A green simulator run means *compiles and logic holds*, nothing more.

**Device test protocol (minimum, before the Phase 3 commit):**
1. 2+ minute continuous dictation — partials < ~1 s; finalized text accurate; segments visible in store *before* Stop, via `DebugSegmentInspectorView` (§3.1 — the persisted count climbs while still recording).
2. Lock at ~30 s, unlock at ~3 min — transcription continuous; UI caught up; memory flat.
3. Incoming call mid-session — pauses with visible state; resumes after hangup; timer excluded the call.
4. AirPods: connect mid-session, then disconnect — no crash, capture continues, transcription resumes on each route within a few seconds.
5. Force-quit mid-sentence — relaunch shows the session with all finalized segments; only the volatile tail is gone.
6. Fresh locale (delete assets / new device): progress UI shows, then transcription works.

### 3.9 Risks & mitigations

| Risk | Mitigation |
|---|---|
| Route change alters input format and silently corrupts/stalls the analyzer feed | Converter rebuilt on `inputFormatChanged`; tap reinstalled with fresh format; AirPods in/out is a mandatory device test, run twice in one session |
| `shouldResume` not delivered after some interruptions (observed iOS behavior varies) | Never rely on auto-resume alone: paused state always renders a manual Resume button |
| Long volatile stretches → user thinks it hung; force-quit loses more | Finalize-through-end-of-input on Stop; durability bar is "at most the volatile tail"; show volatile text live so nothing looks stuck |
| Jetsam during a locked 60-min session | Incremental saves per finalized segment; tap block allocation-free; soak test #1 in PLAN.md §9 watches memory |
| Bluetooth HFP mic (≈16 kHz) degrades accuracy | Accept for V1; converter handles the rate; note in known-issues so it isn't chased as a bug |
| Audio-thread tap doing too much work → dropped buffers | Tap only yields + meters; everything else downstream on the actor/analyzer side |
| Asset download UX dead-ends offline | Explicit failed-download state with retry; Start stays disabled with honest copy |
| SpeechAnalyzer API surface differs in detail from expectations | Trust the spec's stack (no SFSpeechRecognizer fallback path); isolate all SpeechAnalyzer types inside `SpeechAnalyzerTranscriber` so corrections touch one file |

### 3.10 Acceptance gate — commit checklist

Phase 2 gate (commit `feat(phase-2)`):
- [ ] `/build-check` clean; zero new warnings
- [ ] Interruption state-machine tests pass for the full event matrix
- [ ] Device: start/stop ×5 without error; level meter live; elapsed pauses during a self-call and resumes
- [ ] Device: screen locked 2+ minutes — capture continues (buffers still flowing on unlock)
- [ ] No audio object outlives `stop()`; session deactivated with notify-others

Phase 3 gate (commit `feat(phase-3)`):
- [ ] `/build-check` clean; converter, VM, and persistence unit tests pass
- [ ] Device protocol §3.8 items 1–6 all pass, on a physical iPhone
- [ ] Finalized segments are in SwiftData before Stop is tapped (verified via `DebugSegmentInspectorView`, §3.1; cross-checked by the force-quit test, §3.8 item 5)
- [ ] Volatile vs finalized styling correct; auto-scroll holds; unlock catch-up instant
- [ ] Every error state in §3.6 reachable and readable (test by revoking permissions / airplane-mode asset download)
- [ ] Red-dot recording indicator visible whenever capture is active (consent requirement)
- [ ] No networking APIs introduced; no `.xcodeproj` edits; all files in the §3.1 layout

---

## 4. Phases 4 & 6 — Sessions Feature and Document Import

These are the two pure CRUD/UI phases (PLAN.md Phases 4 and 6, data model §8). They have **no dependency on FoundationModels, embeddings, or the audio stack**, which makes them the most simulator-friendly phases in the plan — almost everything here is verifiable in the iPhone 17 Pro simulator, with a short device pass for share-sheet, Files/iCloud, and performance behavior. Both phases also *own contracts that later phases consume*; those contracts are called out explicitly so Phase 5 (summary slot) and Phase 7 (page numbers, chunk cascade, `Document.status`) don't have to reverse-engineer them.

All new files go into existing synchronized folder groups — **never touch the `.xcodeproj`**. New subfolders under `Features/` are fine (synchronized groups pick up the whole tree).

### 4.1 Contracts this section owns (downstream phases depend on these)

1. **Page-break contract (`Document.pageBreaks`, rag.md §6.2 amendment).** §8 stores `Document.textContent` as one string, but Phase 7's chunker needs `pageNumber?` per chunk — and the source PDF is discarded at import, so the stored document must carry everything needed to recover page numbers. Resolution: pages are cleaned individually, then joined with `"\n\n"`; the join computes the UTF-16 offset at which each page starts, and Phase 6 persists those offsets as `Document.pageBreaks: [Int]` (element *i* is the start of page *i + 1*; page 1 starts at offset 0). The field is the additive schema amendment rag.md §6.2 declares — include it in the Phase 1 `SchemaV1` when building from this plan. Phase 7's `TextChunking.chunk(document:pageBreaks:sourceId:)` consumes the persisted offsets to assign `pageNumber` — it never splits the text on a delimiter — so re-index and Rebuild Index reconstruct page-numbered chunks from the store alone. The join helper is unit-tested round-trip: each offset maps back to the correct page.
2. **Cascade-delete rule.** Deleting a Session or Document deletes its `KnowledgeChunk` rows matching `(sourceId, sourceType)`. Chunks are a *loose* reference (not a SwiftData relationship), so the cascade is explicit repository code, in the same `ModelContext` save as the parent delete — no window for orphans.
3. **Summary slot.** `SessionDetailView` renders a `SummarySection(session:)` subview that shows a placeholder in Phase 4; Phase 5 replaces only that subview's body.
4. **`Document.status` lifecycle.** Import always ends at `.imported` ("Not indexed yet" badge). Phase 7 drives `.indexing → .ready/.failed`. UI for all four states is built now so Phase 7 changes no view code.

### 4.2 Phase 4 — Sessions: work breakdown

| File | Purpose |
|---|---|
| `Features/Sessions/SessionsView.swift` | Date-sorted list, `.searchable`, swipe-delete |
| `Features/Sessions/SessionsViewModel.swift` | `@Observable @MainActor`; load, debounced search, delete |
| `Features/Sessions/SessionRow.swift` | Title, date, duration, 2-line preview |
| `Features/Sessions/SessionDetailView.swift` | Transcript, rename, delete-confirm, ShareLink, summary slot |
| `Features/Sessions/SessionDetailViewModel.swift` | Segment loading, rename/delete/export orchestration |
| `Features/Sessions/TranscriptSegmentRow.swift` | `[HH:MM:SS]` timestamp + segment text |
| `Features/Sessions/SessionExporter.swift` | Pure formatting: Markdown / plain text + temp-file writer + `Transferable` export wrapper |
| `Features/Home/HomeView.swift` | 3 action buttons + 3 most recent sessions + empty state |
| `Features/Home/HomeViewModel.swift` | Recent-sessions fetch; navigation intents |
| `Core/Storage/SessionRepository.swift` *(extend Phase 1 file)* | search, preview, rename, cascade delete |
| `Core/Storage/ChunkRepository.swift` *(extend)* | `deleteChunks(sourceId:sourceType:)` |
| `App/AppDependencies.swift` *(extend Phase 1 file)* | Publish `activeSessionID: UUID?`; Phase 3's live-transcription flow sets it on recording start and clears it on stop — an explicit, small touch to that Phase 3 call site made as part of this phase |
| `EchoMindTests/SessionExporterTests.swift` | Golden-output tests for both export formats |
| `EchoMindTests/SessionSearchTests.swift` | In-memory container: title + segment-text search |
| `EchoMindTests/SessionCascadeDeleteTests.swift` | Zero orphaned segments/chunks after delete |

**Repository additions (protocol-first, per CLAUDE.md):**

```swift
protocol SessionRepository: Sendable {
    // existing Phase 1 members… (all snapshot-typed, per foundation.md §2.4)
    func recentSessions(limit: Int?) async throws -> [SessionSnapshot]
    func search(matching query: String) async throws -> [SessionSnapshot]
    func previewText(sessionID: UUID, maxCharacters: Int) async throws -> String
    func rename(sessionID: UUID, to title: String) async throws     // also bumps updatedAt
    // delete(id:) exists since Phase 1 — this phase hardens its cascade: segments + chunks, one save
}

protocol ChunkRepository: Sendable {
    // existing Phase 1 members…
    func deleteChunks(sourceId: UUID, sourceType: SourceType) async throws
}
```

```swift
enum SessionExporter {
    static func markdown(session: SessionSnapshot, segments: [SegmentSnapshot]) -> String
    static func plainText(session: SessionSnapshot, segments: [SegmentSnapshot]) -> String
    /// Writes to FileManager.temporaryDirectory with a sanitized "<title>.md|.txt" name.
    static func temporaryFileURL(contents: String, fileName: String) throws -> URL
}
```

Everything above `Core/Storage` exchanges the Phase 1 snapshot structs (`SessionSnapshot`/`SegmentSnapshot`/`DocumentSnapshot` from `Models/Snapshots.swift`): `@Model` classes are not `Sendable` and never leak past the repositories (foundation.md §2.4), so `Features/` and `Models/` files need no `import SwiftData` and the Phase 1 gate grep (`import SwiftData` only in `Core/Storage` + `App/`) stays green through Phases 4 and 6.

**Search design (transcript is derived from segments — §8 forbids storing it twice).** Two-step query, both off the main actor inside the `@ModelActor` repository (the only place `@Model` objects exist; results cross back as `[SessionSnapshot]`):
1. `FetchDescriptor<TranscriptSegment>` with `#Predicate { $0.text.localizedStandardContains(query) }` and `relationshipKeyPathsForPrefetching: [\.session]` — the Phase 1 schema links segments to sessions via the `session: Session?` relationship (there is no `sessionId` scalar); collect distinct ids in memory from `segment.session?.id`. The predicate itself never traverses the relationship.
2. Fetch `Session` where `title.localizedStandardContains(query) || matchedIds.contains(id)`, sorted by `createdAt` descending; map to snapshots.

The ViewModel debounces `searchText` ~300 ms via a replaced `Task` (cancel previous). `localizedStandardContains` gives case/diacritic-insensitive matching for free. Brute-force is the V1 design (same philosophy as vector search §1); acceptance requires it stays responsive at 5,000 seeded segments.

**2-line preview:** derived lazily — fetch segments for the session sorted by `startTime`, concatenate until ~160 characters, single whitespace-collapse. Never persisted.

**Exact export formats** (golden-tested; timestamps are zero-padded offsets from session start):

```
# {title}                              | {title}
                                       | Date: 2026-07-06 14:32
**Date:** 2026-07-06 14:32            | Duration: 42m 17s
**Duration:** 42m 17s                 |
                                       | [00:00:03] First segment text…
## Transcript                          | [00:00:11] Next segment…
                                       |
**[00:00:03]** First segment text…     |   (plain text, right column)
**[00:00:11]** Next segment…           |
```

Export UI: a toolbar `Menu` containing two `ShareLink`s ("Export as Markdown" / "Export as Text"). `ShareLink` is declarative — it cannot be imperatively presented after a button action — so each link's item is a small `Transferable` wrapper (`SessionExport`, lives in `SessionExporter.swift`) whose `FileRepresentation` runs lazily only when the user actually shares: it formats via `SessionExporter`, writes the temp file into a unique subdirectory with the sanitized `<title>.md`/`.txt` name, and returns a `SentTransferredFile`, so receiving apps get a real filename/extension. The export temp subdirectory is removed `onDisappear`.

**Delete flow:** `confirmationDialog` stating that the transcript *and its knowledge entries* are removed. Order inside the repository: delete chunks → delete segments (SwiftData `.cascade` relationship rule if modeled, else explicit) → delete session → single save.

**Home:** `Start Live Transcript` pushes `LiveTranscriptView` (Phase 3); `Ask My Knowledge` switches to the Ask tab (placeholder until Phase 8); `Import Document` switches to the Knowledge tab now and gains direct `fileImporter` wiring in Phase 6. Recent-3 rows navigate to `SessionDetailView`.

**Phase 4 build order (all Claude Code work; human = device verify only):**
1. Repository extensions + the three unit-test files (foundation; locks cascade + search behavior before any UI).
2. `SessionExporter` + golden tests (freeze the format early — it's user-visible output).
3. `SessionsView` / `SessionRow` / `SessionsViewModel`.
4. `SessionDetailView` stack (transcript via `List` of `TranscriptSegmentRow` — never one giant `Text`; rename as inline `TextField` committed on submit, empty rename reverts).
5. `HomeView` real content + empty states.
6. `/build-check`, simulator pass, then **human:** device pass (share sheet into Mail/Notes, record→list latency), commit `feat(phase-4): sessions`.

### 4.3 Phase 6 — Document import: work breakdown

| File | Purpose |
|---|---|
| `Features/Knowledge/KnowledgeView.swift` | Unified source list, `fileImporter`, swipe-delete |
| `Features/Knowledge/KnowledgeViewModel.swift` | Source aggregation, import orchestration, delete |
| `Features/Knowledge/KnowledgeSourceRow.swift` | Type icon, title, date, size/duration, status badge |
| `Core/Storage/DocumentImportService.swift` | Protocol + impl: scope → read → extract → clean → cap → persist |
| `Core/Storage/PDFTextExtractor.swift` | PDFKit per-page extraction, scanned/locked detection |
| `Core/Storage/TextCleaner.swift` | Pure cleaning functions |
| `Models/KnowledgeSource.swift` | `enum KnowledgeSource { case document(DocumentSnapshot), session(SessionSnapshot) }` — snapshot payloads keep `Models/` free of SwiftData |
| `Models/ExtractedText.swift` | `ExtractedPage {pageNumber, text}`, `ExtractedText {pages, pageCount?}` + `joined()` helper returning `(text: String, pageBreaks: [Int])` |
| `Models/ImportError.swift` | Typed errors with user-facing copy |
| `EchoMindTests/TextCleanerTests.swift` | Hyphen repair, whitespace, control chars, CRLF |
| `EchoMindTests/PDFTextExtractorTests.swift` | Fixtures generated *in test code* (see below) |
| `EchoMindTests/DocumentImportServiceTests.swift` | Caps, encodings, empty files, `pageBreaks` round trip |
| `EchoMindTests/KnowledgeCascadeTests.swift` | Document delete leaves zero chunks |

Import lives in `Core/Storage` (its output is a persisted `Document`); chunking/indexing stays in `Core/RAG` (Phase 7). This keeps the CLAUDE.md folder map intact — no new `Core/` top-level folders.

```swift
protocol DocumentImportService: Sendable {
    /// Full pipeline off the main actor; returns the persisted document's id.
    func importDocument(at url: URL) async throws -> UUID
}

enum ImportError: LocalizedError, Equatable {
    case accessDenied                  // security scope refused
    case unreadable(underlying: String)// includes iCloud not-downloaded failures
    case unsupportedType
    case passwordProtectedPDF
    case scannedPDF                    // "This looks like a scanned PDF. Scanned PDFs aren't supported yet."
    case emptyDocument
    case tooLarge(limitMB: Int)        // "…more than 5 MB of text…"
}
```

**Pipeline (in order, each step failable with a distinct `ImportError`):**
1. `url.startAccessingSecurityScopedResource()` — `defer { stop }`; if `false` → `.accessDenied`. Read `Data` **inside** the scope, immediately, off the main actor; never hold the URL for later reads.
2. Raw-size guard before extraction (50 MB PDF / 5 MB txt-md) so a huge file never fully loads just to fail the text cap.
3. Type routing by `UTType`: `.pdf` → `PDFTextExtractor`; `.plainText` and `UTType(filenameExtension: "md")` → decode with an explicit try-in-order list via `String(data:encoding:)`: `.utf8` first, then `.windowsCP1252`, then `.isoLatin1` (Latin-1/CP1252 exports are common; `.isoLatin1` accepts any byte sequence, so the chain always yields a string). Result is one pseudo-page with `pageNumber = nil`. (No `usedEncoding:` API applies here — Foundation has no `String(data:usedEncoding:)`, and the URL-based variants are ruled out because step 1 forbids holding the URL; if smarter detection is ever wanted, the `Data`-based option is `NSString.stringEncoding(for:encodingOptions:convertedString:usedLossyConversion:)`.)
4. PDF checks: `PDFDocument(data:)` nil → `.unreadable`; `isLocked` → `.passwordProtectedPDF`. Extract `page.string` per page (autoreleasepool per page to bound memory on image-heavy PDFs).
5. **Cleaning (per page, pure & unit-tested):** CRLF→LF; strip Unicode `Cc` except `\n`/`\t`; repair hyphenated line breaks with `([A-Za-z])-\s*\n\s*([a-z])` → `$1$2` (lowercase continuation only, so legit hyphens like "V1-only" survive); collapse space/tab runs; collapse 3+ newlines to 2; trim line trailing whitespace.
6. **Scanned detection (on the cleaned pages):** if `pageCount ≥ 1` and total cleaned text < max(50, 10 × pageCount) characters → `.scannedPDF`. Mixed PDFs (some scanned pages) pass — only text pages contribute; no OCR in V1.
7. Join cleaned pages with `"\n\n"` via `ExtractedText.joined()`, which also returns `pageBreaks` — the UTF-16 offset into the joined text at which each page starts (the rag.md §6.2 contract). If the joined text is empty → `.emptyDocument`; if UTF-8 byte count > 5 MB → `.tooLarge(limitMB: 5)`.
8. Persist via `DocumentRepository.create(DocumentSnapshot(title: filename-sans-extension, fileName, fileType, textContent, pageCount, pageBreaks, status: .imported))` — writing `pageBreaks` at import time is what lets Phase 7 index and rebuild page-numbered chunks after the PDF is gone. Duplicate filenames are allowed (no dedupe in V1).

**Knowledge tab.** `KnowledgeViewModel` merges `DocumentRepository.fetchAll()` (`[DocumentSnapshot]`) and `SessionRepository.recentSessions(limit: nil)` (`[SessionSnapshot]`) into `[KnowledgeSource]` sorted by date. Rows: `doc.text`/`doc.richtext` icon + formatted byte size for documents; `waveform` icon + duration for sessions; `.imported` shows a subtle "Not indexed yet" badge (honest until Phase 7 — Ask can't see un-indexed sources). Swipe-delete: documents delete row + chunks after a confirmation; **session rows warn that the entire session and transcript will be deleted** and then run the same cascade as the Sessions tab — one mental model: delete means gone everywhere (a de-index-only alternative was rejected as a V1 complexity trap). `fileImporter(allowedContentTypes: [.pdf, .plainText, UTType(filenameExtension: "md")].compactMap { $0 }, allowsMultipleSelection: false)` — single file in V1. Import runs in a `Task` with a progress row pinned atop the list; errors surface as an alert using `ImportError.errorDescription`.

**PDF test fixtures need no human assets:** tests render a multi-page text PDF with `UIGraphicsPDFRenderer` + `NSAttributedString.draw`, and a "scanned" fixture by rendering only a bitmap into a page — both created at test runtime.

**Phase 6 build order (all Claude Code; human = real-file device pass):**
1. `TextCleaner` + tests (pure, zero dependencies).
2. `ExtractedText` (incl. the `joined()`/`pageBreaks` helper) and `ImportError` models, then `PDFTextExtractor` + generated-fixture tests.
3. `DocumentImportService` + tests (caps, encodings, empty, `pageBreaks` round trip, scanned threshold).
4. `KnowledgeView` stack + cascade tests.
5. Wire Home's `Import Document` to present the importer directly.
6. `/build-check`, simulator pass with dragged-in files, then **human:** device pass, commit `feat(phase-6): document import`.

### 4.4 Edge cases and failure modes

| Case | Handling |
|---|---|
| Session with zero segments (instant stop) | Empty preview; export still emits valid header; detail shows "No transcript" |
| Delete attempted on the actively recording session | Delete disabled while `AppDependencies.activeSessionID` (the published property added by this phase's `AppDependencies` work item, set/cleared by Phase 3's start/stop path) matches that session id |
| Rename to empty/whitespace | Revert to previous title, no save |
| Very long transcripts | `List` + per-segment rows only; never concatenate into one `Text` |
| Search while typing | Debounce + task cancellation; stale results never overwrite newer ones |
| ShareLink temp files | Written lazily by the `FileRepresentation` wrapper into a unique subdirectory per export, removed `onDisappear` |
| iCloud file not downloaded | Read fails inside scope → `.unreadable` with "Download it in Files first" copy |
| Password-protected PDF | `.passwordProtectedPDF`, friendly copy |
| Mixed scanned/text PDF | Accepted; only text pages contribute (documented behavior) |
| `.txt` in non-UTF-8 encoding | UTF-8 → CP1252 → Latin-1 fallback chain (pipeline step 3) decodes it; exotic encodings may decode imperfectly but never hard-fail |
| Import cancelled via sheet dismissal | `fileImporter` returns `.failure`/no-op; nothing persisted |
| Kill mid-import | Persist happens as one save at the end — either full row or nothing |

### 4.5 Test strategy — unit vs. simulator vs. device

- **Unit (in-memory `ModelContainer`):** exporter golden strings; search over titles + segments; cascade deletes (assert zero orphans by re-querying segments and chunks); all `TextCleaner` rules; scanned-detection threshold; 5 MB cap; `pageBreaks` round trip (each persisted offset reconstructs the correct `pageNumber`); encoding fallback.
- **Simulator is sufficient for:** all list/detail UI, `fileImporter` with files dragged into the simulator, swipe actions, empty states, status badges.
- **Physical device required (human):** share-sheet handoff to real apps (Mail renders the `.md` attachment correctly); Files-app + iCloud Drive picks including a not-yet-downloaded file; a real 30-page PDF and a genuinely scanned PDF; search responsiveness with a seeded ~5,000-segment store; and a **regression check that Phase 2/3 recording still persists segments** after the repository changes and the `activeSessionID` touch to the Phase 3 start/stop path. As throughout this plan, simulators cannot validate mic capture quality, background audio, Foundation Models availability, or real performance — nothing in these two phases touches the first three, but the recording regression check keeps that guarantee honest. No new entitlements, Info.plist keys, or signing changes are needed for either phase, so there is no App Store Connect / Xcode-GUI human work here.

### 4.6 Section-specific risks

| Risk | Mitigation |
|---|---|
| SwiftData `#Predicate` limits on cross-model search | Two-step query is the design from day one (segments → ids → sessions); no relationship traversal in predicates |
| Brute-force search degrades on large stores | Seeded 5k-segment perf check in the gate; step 1 fetches only matching segments with the `session` relationship prefetched; V1.1 slot for a search index |
| Persisted `pageBreaks` drift out of sync with `textContent` | One shared `joined()` helper produces the joined text *and* its offsets in the same pass (never computed separately); cleaning is per page and finished *before* the join, so nothing mutates the text after offsets are taken; round-trip unit test maps each offset back to the correct `pageNumber` |
| PDFKit extraction quality (multi-column, headers/footers) | Accepted V1 limitation; cleaning reduces noise; noted for V1.1 alongside OCR |
| Memory spikes on image-heavy PDFs | Raw-size guard + per-page autoreleasepool extraction |
| Orphaned chunks from sourceType mismatch | One shared `SourceType` enum (Phase 1) used by repositories, chunker, and cascade tests |
| Users confused why imported docs don't answer questions yet | Explicit "Not indexed yet" badge until Phase 7 flips status |

### 4.7 Acceptance gate (commit gate)

**Phase 4 — commit `feat(phase-4): sessions` only when all pass:**
- [ ] A session recorded in Phase 3 appears in `SessionsView` immediately after Stop, with correct title, date, duration, 2-line preview
- [ ] Search matches title-only hits and transcript-only hits; clearing the query restores the full list; 5k-segment store stays responsive on device
- [ ] Rename persists across relaunch; empty rename reverts
- [ ] Delete confirmation cascades: re-query shows zero `TranscriptSegment` and zero `KnowledgeChunk` for that id (unit test + manual)
- [ ] Markdown and plain-text exports match the golden format; both open correctly from Mail/Notes on device
- [ ] Home shows the 3 most recent sessions and all three actions navigate; empty states render on fresh install
- [ ] Summary placeholder slot renders (Phase 5 hook point exists)
- [ ] `/build-check` clean; all Phase 4 unit tests green; recording regression check passed on device

**Phase 6 — commit `feat(phase-6): document import` only when all pass:**
- [ ] Multi-page text PDF imports: correct title, page count, `.imported` badge, size shown
- [ ] `.md` and `.txt` (including a Latin-1 `.txt`) import; hyphenated line breaks repaired in stored text
- [ ] Scanned PDF rejected with the friendly copy; password-protected PDF rejected distinctly; >5 MB extracted text rejected with the cap message
- [ ] `Document.pageBreaks` persisted at import; round-trip test green — offsets reconstruct correct page numbers (Phase 7 contract, rag.md §6.2)
- [ ] Knowledge tab lists documents *and* session transcripts, sorted by date, correct icons/metadata
- [ ] Swipe-delete on a document removes it and all its chunks; on a session, warns and cascades like the Sessions tab
- [ ] Import from iCloud Drive works on device (downloaded file), and an undownloaded file fails with actionable copy
- [ ] `/build-check` clean; all Phase 6 unit tests green

---

## 5. Phase 5 — AI Core: ModelGateway, TokenBudgeter, Map-Reduce Summarizer

**Goal:** the entire on-device generation stack — a swappable model gateway, hard token budgeting, guided-generation `MeetingSummary`, and a map-reduce summarizer wired into `SessionDetailView` — with the PLAN.md §3 budgets enforced as arithmetic, not vibes. Prereqs: Phases 1–4 committed (SwiftData models, `AppDependencies`, `SessionDetailView` with its summary placeholder).

### 5.1 Work breakdown — files to create

| File | Contents |
|---|---|
| `Core/AI/ModelGateway.swift` | `ModelGateway` protocol + `ModelGatewayError` |
| `Core/AI/ModelAvailability.swift` | `AvailabilityStatus` + `AvailabilityProviding` protocol + `@Observable` `ModelAvailabilityMonitor` |
| `Core/AI/FoundationModelService.swift` | `ModelGateway` impl over `SystemLanguageModel`/`LanguageModelSession` |
| `Core/AI/TokenBudgeter.swift` | `TokenCounting` protocol, estimator + native (26.4+) counters, `TokenBudgeter` |
| `Core/AI/Summarizer.swift` | `SegmentText` value snapshot, `SummarizerService` protocol, `MapReducePlan` (pure), `MapReduceSummarizer` |
| `Core/AI/SummaryPrompts.swift` | The fixed map/reduce instruction strings — single source of truth so budget math is stable |
| `Models/MeetingSummary.swift` | `@Generable` + `Codable` summary types |
| `Core/Storage/DebugFixtures.swift` | Deterministic ~9,000-word fixture transcript generator (DEBUG only) |
| `Features/Sessions/SummarySectionView.swift` | Structured summary rendering + Tier B explanation + progress UI |
| `Features/Sessions/SessionDetailViewModel.swift` | Extend (exists from Phase 4): summary state machine |
| `EchoMindTests/MockModelGateway.swift` | Scriptable gateway: canned responses, injectable `exceededContextWindowSize`; `MockAvailabilityProvider` with settable `status` |
| `EchoMindTests/TokenBudgeterTests.swift` | Estimator, `fit`, `pack` |
| `EchoMindTests/MapReducePlanTests.swift` | Windowing on segment boundaries |
| `EchoMindTests/SummarizerRetryTests.swift` | Overflow → re-split → retry → clear error, via mock |
| `EchoMindTests/MeetingSummaryPersistenceTests.swift` | JSON round-trip into `Session.summaryJSON` |

All new files land inside existing synchronized folder groups — **zero `.xcodeproj` edits**. Register `tokenBudgeter`, `modelGateway`, `availabilityMonitor`, `summarizer` in `AppDependencies`; view models see protocols only.

### 5.2 ModelGateway — the V1.1 seam

```swift
// Core/AI/ModelGateway.swift
import FoundationModels

protocol ModelGateway: Sendable {
    /// Free-form text. One fresh underlying session per call.
    func respond(instructions: String, prompt: String, maxOutputTokens: Int) async throws -> String
    /// Guided generation into a @Generable type. One fresh session per call.
    func generate<T: Generable & Sendable>(instructions: String, prompt: String, as type: T.Type) async throws -> T
}

enum ModelGatewayError: Error, Equatable {
    case exceededContextWindow          // normalized from FoundationModels' error
    case modelUnavailable(AvailabilityStatus)
    case guardrailViolation             // safety refusal — user-readable, never a crash
    case generationFailed(String)
}
```

Design rules that make the iOS 27 PCC/third-party swap (PLAN.md §10) a drop-in:

- Call sites take `any ModelGateway` from `AppDependencies`; nothing outside `Core/AI` imports `FoundationModels` **except** the `Generable` conformance on `MeetingSummary`. Judgment call: `Generable` is the one framework type allowed in the seam — iOS 27's `LanguageModel` protocol keeps guided generation, so abstracting it away in V1 is over-engineering.
- `FoundationModelService` normalizes framework errors into `ModelGatewayError` so retry logic in `Summarizer`/`RAGPipeline` never pattern-matches framework error types.
- `maxOutputTokens` maps to `GenerationOptions(maximumResponseTokens:)` inside the implementation.
- **One fresh `LanguageModelSession` per call**, constructed with `Instructions` inside `respond`/`generate` and discarded on return. The service holds no session property — that is how "never accumulate history" is made structurally impossible, not just a convention.

```swift
// Core/AI/ModelAvailability.swift
enum AvailabilityStatus: Equatable, Sendable {
    case tierA
    case tierB(TierBReason)
    enum TierBReason: Equatable, Sendable {
        case deviceNotEligible          // hardware can never do it
        case appleIntelligenceNotEnabled// actionable: point at iOS Settings
        case modelNotReady              // transient: downloading/preparing
        case unknown
    }
}

@MainActor
protocol AvailabilityProviding: AnyObject {
    var status: AvailabilityStatus { get }
    func refresh()
}

@Observable @MainActor
final class ModelAvailabilityMonitor: AvailabilityProviding {
    private(set) var status: AvailabilityStatus = .tierB(.unknown)
    func refresh()  // maps SystemLanguageModel.default.availability; call at launch + scenePhase .active
}
// MockAvailabilityProvider (test target) conforms with a settable status, so
// availability-driven ViewModel states (.requiresAppleIntelligence(reason))
// are scriptable in unit tests.
```

The three `.unavailable` reasons must stay distinct end-to-end: Settings shows the specific reason, `deviceNotEligible` copy is terminal ("this iPhone doesn't support Apple Intelligence"), `appleIntelligenceNotEnabled` links the user to Settings, `modelNotReady` says "try again shortly". Refresh on foregrounding is what makes toggling Apple Intelligence off/on reflect without relaunch. Per the CLAUDE.md hard rule (every service = protocol + one implementation), `AppDependencies` registers the monitor as `any AvailabilityProviding`; `SessionDetailViewModel` and Settings depend on the protocol, never on the concrete class.

### 5.3 TokenBudgeter — every call goes through it

```swift
// Core/AI/TokenBudgeter.swift
protocol TokenCounting: Sendable { func count(_ text: String) -> Int }

struct EstimatedTokenCounter: TokenCounting {
    let charsPerToken: Double            // 3.5 normally; 3.0 for the conservative retry pass
    func count(_ text: String) -> Int { Int(ceil(Double(text.count) / charsPerToken)) }
}
// NativeTokenCounter: wraps tokenCount(for:) when the OS provides it (iOS 26.4+),
// selected at runtime via #available / API presence. Never hardcode 4_096:
// contextSize comes from SystemLanguageModel when exposed; a single fallback
// constant lives HERE and nowhere else.

struct TokenBudgeter: Sendable {
    let contextSize: Int
    let counter: TokenCounting

    func tokens(in text: String) -> Int
    func fit(instructions: String, prompt: String, reservedOutput: Int) -> Bool
    /// Adds ranked items in order until budget is exhausted; never splits an item.
    func pack(items: [String], budget: Int) -> (included: [String], usedTokens: Int)
}
```

`fit` returns whether `tokens(instructions) + tokens(prompt) + reservedOutput <= contextSize`. `pack` is shared with Phase 8 RAG. `FoundationModelService` asserts `fit(...)` in DEBUG before every call so an unbudgeted call fails loudly in development.

**Budget arithmetic sanity check (must appear as a comment atop `SummaryPrompts.swift`):**

| Call | Input | Output reserve | Total | Headroom vs 4,096 |
|---|---|---|---|---|
| Map | map instructions ≤150 + window ≤2,200 | 300 | ≤2,650 | ≥1,446 (~35%) |
| Reduce | reduce instructions ~200 + schema ~150 + partials ≤2,150 (≤2,500 total) | 700 | ≤3,200 | ≥896 (~22%) |

Headroom absorbs estimator error (±15% typical) plus the guided-generation schema, which counts against reduce input — budget a fixed `schemaOverhead ≈ 150` tokens inside the 2,500. Max partials per reduce: `(2,500 − 200 instr − 150 schema) / 300 ≈ 7` → single-level reduce covers ~7 × 2,200 = 15,400 input tokens ≈ ~90 minutes of speech. Beyond that, run an **intermediate reduce** (merge partials in groups of ≤7, then reduce the merged partials) — recursive, every level still budgeted.

### 5.4 @Generable MeetingSummary

```swift
// Models/MeetingSummary.swift
import FoundationModels

@Generable
struct MeetingSummary: Codable, Equatable, Sendable {
    @Guide(description: "2-4 sentence overview of what the meeting covered")
    var overview: String
    @Guide(description: "Concrete decisions that were made, one per entry")
    var keyDecisions: [String]
    var actionItems: [ActionItem]
    var risks: [String]
    var openQuestions: [String]

    @Generable
    struct ActionItem: Codable, Equatable, Sendable {
        var text: String
        @Guide(description: "Person responsible, only if explicitly named")
        var owner: String?
    }
}
```

Guided generation does constrained decoding against this schema — the model *cannot* return free-form prose or malformed JSON, which eliminates the parse-and-pray failure mode of prompting for JSON. Keep the schema flat and `@Guide` strings short: every character of schema is input tokens in the reduce call. Persistence: `JSONEncoder` → `Session.summaryJSON` (data model §8); `Codable` conformance is ours, independent of `Generable`. If decoding a stored summary ever fails (schema drift across app versions), render "Summary format outdated — regenerate", never crash.

### 5.5 Summarizer — map-reduce exactly per §3

```swift
// Core/AI/Summarizer.swift
enum SummarizerProgress: Equatable, Sendable {
    case planning
    case mapping(window: Int, of: Int)
    case reducing
}

/// Sendable value snapshot of a TranscriptSegment. SwiftData @Model objects
/// are not Sendable and must never cross the summarizer boundary under the
/// spec's Swift 6 strict concurrency — snapshot on the ModelContext's actor,
/// then hand these values across.
struct SegmentText: Equatable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
}

protocol SummarizerService: Sendable {
    func summarize(
        segments: [SegmentText],
        onProgress: @Sendable @escaping (SummarizerProgress) -> Void
    ) async throws -> MeetingSummary
}

/// Pure and unit-testable: no model, no I/O.
struct MapReducePlan: Equatable {
    let windows: [[SegmentText]]   // each window ≤ 2,200 input tokens
    static func make(segments: [SegmentText], budgeter: TokenBudgeter) -> MapReducePlan
}
```

`MapReduceSummarizer` algorithm:

1. **Plan.** Greedily pack whole segments into windows of ≤2,200 tokens (segment boundaries only). Edge case: a single segment >2,200 tokens (uninterrupted monologue) is hard-split on sentence boundaries inside the planner.
2. **Skip-map shortcut.** If `windows.count == 1` **and** the window fits the reduce input budget — window tokens ≤ 2,500 − ~200 reduce instructions − ~150 `schemaOverhead` ≈ **2,150** — skip map entirely: one `generate(...as: MeetingSummary.self)` call with the transcript as prompt, reduce budgets applied (≤2,500 input incl. instructions and schema, 700 output). A single window in the 2,151–2,200 band is *not* eligible — it runs the normal map→reduce path — so the DEBUG `fit` assertion at the reduce budget can never fire spuriously.
3. **Map.** Per window, `respond(instructions: SummaryPrompts.map, prompt: windowText, maxOutputTokens: 300)`. Map instructions demand plain-text bullets that preserve verbatim names, dates, numbers, and decisions — reduce quality dies if partials are vague. Windows run **sequentially** (judgment call: the on-device model serializes anyway; sequential keeps memory flat and progress honest).
4. **Reduce.** Concatenate partials (labelled "Part 1/7…"), `generate(...as: MeetingSummary.self)` under the reduce budgets. >7 partials → intermediate reduce per §5.3.
5. **Overflow recovery (spec rule).** Catch `.exceededContextWindow` from any call → re-split the offending window once using the conservative counter (`charsPerToken: 3.0`), retry that call; if it overflows again, throw a clear user-facing error ("This session is too long to summarize") — never a crash, never a silent truncation.
6. Check `Task.isCancelled` between every model call; on cancellation discard partials and rethrow `CancellationError`.

### 5.6 SessionDetailView wiring

`SessionDetailViewModel` gains a summary state machine:

```swift
enum SummaryState: Equatable {
    case none                              // Tier A, no stored summary → "Generate Summary" button
    case generating(SummarizerProgress)    // "Summarizing part 2 of 7…" + ProgressView; cancel on disappear
    case available(MeetingSummary)         // structured sections + "Regenerate"
    case failed(String)                    // clear message + retry
    case requiresAppleIntelligence(AvailabilityStatus.TierBReason)  // Tier B explanation, no button
}
```

- `SessionDetailViewModel` (`@MainActor`, where the ModelContext-bound `Session` lives) snapshots segments into `[SegmentText]` *before* calling `summarize` — no `@Model` object crosses into the summarizer (§5.5).
- `SummarySectionView` renders Overview, Key Decisions, Action Items (owner badge when present), Risks, Open Questions; empty arrays collapse their section.
- **Regenerate replaces**: keep the old summary rendered until the new one succeeds, then overwrite `summaryJSON` in one save. A failed regenerate must not destroy the existing summary.
- Tier B: reason-specific copy (per §5.2), plus the reminder that transcription/sessions/export still work — this is a feature gate, not an error screen.
- Availability observed live from the injected `any AvailabilityProviding`, so toggling Apple Intelligence off and returning to the app flips the view state.

### 5.7 Debug fixture — deterministic map-reduce testing

`Core/Storage/DebugFixtures.swift` (DEBUG only), reachable from the Phase 1 debug menu as "Insert 9,000-word fixture session":

- **Generated in code, seeded and deterministic** (judgment call: avoids bundled-resource questions and guarantees byte-identical runs). Emits ~9,000 words as ~150 segments with realistic timestamps — inserted as `TranscriptSegment`s from the debug menu, and exposed as `[SegmentText]` so `MapReducePlanTests` consume it directly. Pure DEBUG code with no model dependency, which is why it builds at step 4 of §5.8, ahead of the tests that need it.
- Sized deliberately at the reduce ceiling: ~9,000 words ≈ 49k chars ≈ 14k estimated tokens → **7 map windows** → 7 × 300 = 2,100 partial tokens + instructions + schema ≈ 2,450 → exercises multi-window map *and* maximally-full single-level reduce in one artifact.
- Embeds **known ground truth** — numbered decisions ("Decision D3: move billing migration to Q3"), owners ("Priya owns the vendor audit"), risks, open questions — so a human can eyeball recall in the generated summary, and unit tests can assert the *plan* (window count, boundaries) exactly.

### 5.8 Ordered build steps

| # | Step | Who |
|---|---|---|
| 1 | `TokenBudgeter` + counters + tests — pure logic, everything downstream depends on it | Claude Code |
| 2 | `ModelGateway` protocol, `ModelGatewayError`, `AvailabilityStatus`, `AvailabilityProviding`, `MockModelGateway` + `MockAvailabilityProvider` | Claude Code |
| 3 | `MeetingSummary` + JSON persistence round-trip test | Claude Code |
| 4 | Debug fixture generator + debug-menu insertion (pure DEBUG code, no model dependency — step 5's tests consume it) | Claude Code |
| 5 | `MapReducePlan` (pure windowing) + tests incl. oversized-segment split and the 9,000-word-fixture window-count assertion | Claude Code |
| 6 | `MapReduceSummarizer` against the mock: skip-map path (incl. the ineligible 2,151–2,200 band), 7-window path, overflow→re-split→retry→clear-error path, cancellation | Claude Code |
| 7 | `FoundationModelService` + `ModelAvailabilityMonitor`; register in `AppDependencies` | Claude Code |
| 8 | `SessionDetailView`/ViewModel wiring, `SummarySectionView`, Settings model-status row | Claude Code |
| 9 | Build clean via `/build-check`; full simulator test pass | Claude Code |
| 10 | **Device verification on a Tier A iPhone** (Apple Intelligence on): fixture summary end-to-end | Human |
| 11 | **Toggle Apple Intelligence off** (Settings → Apple Intelligence & Siri), re-enter app, confirm Tier B state + reason; toggle back on, confirm `modelNotReady` → `tierA` progression | Human |
| 12 | Airplane-mode run of step 10 (proves zero-network summarization) | Human |

Steps 1–6 are deliberately model-free: they compile and test in the simulator before any `FoundationModels` runtime behavior is needed.

### 5.9 Edge cases and failure modes

- **Overflow mid-map / mid-reduce** → §5.5 rule 5. Retry uses the 3.0 chars/token counter; exactly one retry per call.
- **Guardrail/safety refusal** → `.guardrailViolation` → "Couldn't summarize this content." Stored summary untouched.
- **Empty or tiny transcript** (< ~50 tokens): skip the model, show "Not enough transcript to summarize."
- **Non-Latin scripts**: 3.5 chars/token overestimates capacity for CJK — the ~22–35% headroom plus the conservative retry is the V1 answer; the native counter (26.4+) is the real fix.
- **`modelNotReady` at button-tap time** (model unloaded under memory pressure, mid-download): treat as transient — one internal retry after refresh, then `.failed` with "model is preparing" copy.
- **View disappears mid-generation**: task cancelled, no partial writes, state back to `.none`/`.available`.
- **App backgrounded mid-generation**: no background entitlement for inference — accept suspension; on foreground, resume if the task survived, otherwise surface `.failed` with a retry.
- **Unit-test in simulator:** everything in steps 1–6, plus ViewModel state transitions with the mock gateway and `MockAvailabilityProvider` (including the `.requiresAppleIntelligence(reason)` states).
- **Simulator generation:** on an Apple Silicon Mac running macOS 26 with Apple Intelligence enabled, the iOS 26 simulator *can* report `.available` and run real generation (backed by the host model) — use it to iterate on prompts and guided-generation output before device time. It is not acceptance: it says nothing about device latency/thermals, tier behavior on real hardware, or availability transitions.
- **Device-only — must be validated on hardware:** generation latency and thermals, real availability transitions (Apple Intelligence toggling, `modelNotReady` progression), airplane-mode operation, and (from earlier phases) mic capture and background audio. The Tier A device pass in steps 10–12 remains the acceptance gate; a green simulator run — even one that generates — does not replace it.

### 5.10 Acceptance gate — commit `feat(phase-5): ai core + summaries`

- [ ] Build + full test suite clean; no new warnings
- [ ] `TokenBudgeter` tests pass: estimator, `fit`, `pack`, contextSize not hardcoded anywhere else (grep for `4096`/`4_096` finds only the single fallback constant)
- [ ] `MapReducePlan` tests: 9,000-word fixture → expected window count; no window >2,200 est. tokens; oversized single segment splits on sentences
- [ ] Mock-gateway tests: skip-map on a single window within the ~2,150-token reduce-eligible budget, map→reduce for a single window above it; overflow → re-split → retry once → clear error; cancellation discards partials
- [ ] `FoundationModelService` provably creates a fresh session per call (no stored session property; code-review check)
- [ ] Device (Tier A): fixture session summarizes with **zero** context-window errors; all five sections render; ground-truth decisions/owners recognizably present
- [ ] Device: regenerate replaces the stored summary; failed regenerate preserves the old one
- [ ] Device: Apple Intelligence off → "Requires Apple Intelligence" with the *not-enabled* reason; back on → returns to Tier A without reinstall
- [ ] Device: summary generation works in airplane mode
- [ ] `summaryJSON` round-trips; undecodable stored JSON degrades to a regenerate prompt

### 5.11 Section risks

| Risk | Mitigation |
|---|---|
| Char-estimate drifts from the real tokenizer → intermittent overflows on device | 22–35% headroom by construction; conservative retry counter; adopt `tokenCount(for:)` the moment 26.4 is the floor |
| Guided-generation schema overhead eats the reduce budget | Fixed 150-token `schemaOverhead` inside the 2,500; flat schema; short `@Guide` strings; verify on device with the fixture |
| Reduce output is generic mush (partials lost specifics) | Map instructions mandate verbatim names/dates/numbers; fixture ground truth makes regressions visible at review time |
| Very long meetings (>~90 min) exceed single-level reduce | Recursive intermediate reduce, already budgeted; test with a doubled fixture |
| Availability flapping mid-flow (toggle, memory pressure) | Single monitor as source of truth, refresh on foreground, transient-vs-terminal reasons handled distinctly |
| Gateway seam silently leaks FoundationModels types, jamming the V1.1 swap | Only `Generable` is permitted in the protocol surface; errors normalized to `ModelGatewayError`; enforce at code review |

---

## 6. Phases 7–8 — Chunking, Embeddings, Vector Search & Ask (RAG)

**Scope:** the retrieval half of Core/RAG (Phase 7: TextChunker, EmbeddingService, vector packing, Indexer, VectorSearch) and the Ask feature (Phase 8: RAGPipeline + AskView). Depends on Phases 1–6: SwiftData models (`KnowledgeChunk`, `ChatMessage` per PLAN.md §8), `TokenBudgeter` + `ModelGateway`/`FoundationModelService` (Phase 5), and document import (Phase 6) — which, per the spec §8 amendment declared in §6.2, must persist per-page break offsets on `Document` so indexing and rebuilds can recover page numbers from the store alone. Token budgets are the PLAN.md §3 numbers — treat them as compile-time constants of the design, not tunables.

### 6.1 Work breakdown — files to create

All new files go inside existing synchronized folder groups; **never touch the .xcodeproj**.

| File | Purpose |
|---|---|
| `Models/TextChunk.swift` | Pre-persistence chunk value type (text + metadata), `RetrievedChunk` (chunk + score) |
| `Core/RAG/TextChunker.swift` | Sentence-boundary chunking, ~200-word chunks / ~40-word overlap |
| `Core/RAG/EmbeddingService.swift` | `EmbeddingService` protocol only |
| `Core/RAG/NLContextualEmbeddingService.swift` | NLContextualEmbedding impl: asset ensure/download, mean-pool, L2-normalize, batching |
| `Core/RAG/VectorPacking.swift` | `[Float] <-> Data` little-endian pack/unpack with validation |
| `Core/RAG/VectorSearch.swift` | Brute-force cosine via vDSP dot on pre-normalized vectors, top-K |
| `Core/RAG/IndexerService.swift` | `IndexerService` protocol + `RAGIndexer` impl (chunk → embed → store, progress, rebuild) |
| `Core/RAG/RAGPipeline.swift` | Question embedding → retrieve → budget-pack → grounded answer / fallback ladder |
| `Features/Ask/AskView.swift` | Chat UI over `ChatMessage` storage |
| `Features/Ask/AskViewModel.swift` | `@MainActor` VM: send question, streaming states, persistence, tier gating |
| `Features/Ask/AnswerCardView.swift` | Answer card + retrieval-only card variants |
| `Features/Ask/SourceSnippetView.swift` | Snippet row: preview, title, page/timestamp, tap-through |
| `Features/Knowledge/DocumentDetailView.swift` | Document reader (Phase 8): per-page rendering of `Document.textContent`, scroll-to-page — the `.document` tap-through target. Phase 6 ships only the Knowledge list (`KnowledgeView`/`KnowledgeSourceRow`), so this screen is built here, not assumed |
| `EchoMindTests/TextChunkerTests.swift` | Boundary/overlap/metadata tests |
| `EchoMindTests/VectorPackingTests.swift` | Round-trip + malformed-Data tests |
| `EchoMindTests/VectorSearchTests.swift` | Cosine vs hand-computed, top-K ordering |
| `EchoMindTests/RAGPipelineTests.swift` | Budget packing, fallback ladder, not-found path (mock gateway + mock embedder) |

Deliberately **not** created: no new source-type enum and no new source-ref struct. These phases reuse Phase 1's shared types — `SourceType` (`Models/SourceType.swift`, `document`/`session` cases) and `SourceRef` (`Models/SourceRef.swift`, already JSON-encoded into `ChatMessage.sourceRefsData` since Phase 1). A second parallel enum for the same concept is precisely the sourceType-mismatch orphan-chunk failure that sessions-import's cascade design guards against: `ChunkRepository.deleteChunks(sourceId:sourceType:)` takes the shared `SourceType`, so the chunker, indexer, pipeline, and cascade tests must all speak that one type.

Files to **modify**: `Features/Knowledge/KnowledgeViewModel.swift` (indexing progress, `.indexing → .ready` status — persisted `Document.status` for document rows, in-memory event-driven status for session rows; see §6.2), `Features/Knowledge/KnowledgeView.swift` (document rows navigate to the new `DocumentDetailView`; see §6.3), `Features/Settings/SettingsView(.swift)/ViewModel` (Rebuild Index row), `AppDependencies` (register the four new services), Phase 3's session-save path (trigger indexing on session stop), Phase 6's import completion (trigger indexing; PDF extraction must also persist `Document.pageBreaks` per the §6.2 amendment), and the `Core/Storage` model files for the two schema amendments (`Document.pageBreaks`, `AppSettings.embeddingDimension`).

Keep every file under ~300 lines (CLAUDE.md); `RAGIndexer` and `RAGPipeline` are the two most at risk — split prompt-assembly helpers out if needed.

### 6.2 Key contracts

These signatures pin the design; view models depend only on the protocols.

```swift
// Models/TextChunk.swift
struct TextChunk: Sendable, Equatable {
    let text: String
    let sourceId: UUID
    let sourceType: SourceType       // shared Phase 1 enum (Models/SourceType.swift): .document | .session
    let chunkIndex: Int
    let pageNumber: Int?             // documents only
    let timestamp: TimeInterval?     // startTime of first contributing segment (sessions)
}

// Core/RAG/TextChunker.swift — pure, synchronous, fully unit-testable
protocol TextChunking: Sendable {
    // pageBreaks are plain integer UTF-16 offsets into `text` — persistable and
    // store-safe. Never String.Index: an index is only valid for the exact String
    // instance that produced it and cannot survive persistence or a store round-trip.
    func chunk(document text: String, pageBreaks: [(pageNumber: Int, utf16Offset: Int)],
               sourceId: UUID) -> [TextChunk]
    func chunk(segments: [(text: String, startTime: TimeInterval)],
               sourceId: UUID) -> [TextChunk]
}

// Core/RAG/EmbeddingService.swift
protocol EmbeddingService: Sendable {
    var dimension: Int { get async throws }   // resolved after asset load; never hardcoded
    func embed(_ texts: [String]) async throws -> [[Float]]  // L2-normalized, one vector per input
    func prepareAssets() async throws          // ensure/download language asset; idempotent
}

// Core/RAG/VectorPacking.swift
enum VectorPacking {
    static func pack(_ vector: [Float]) -> Data                    // little-endian
    static func unpack(_ data: Data, expectedDimension: Int) throws -> [Float]
}

// Core/RAG/VectorSearch.swift — vectors pre-normalized, so dot == cosine
struct VectorSearch: Sendable {
    func topK(query: [Float], candidates: [(id: UUID, vector: [Float])],
              k: Int) -> [(id: UUID, score: Float)]
}

// Core/RAG/IndexerService.swift
enum IndexingEvent: Sendable { case progress(sourceId: UUID, fraction: Double)
                               case finished(sourceId: UUID)
                               case failed(sourceId: UUID, error: Error) }
protocol IndexerService: Sendable {
    func indexDocument(id: UUID) async throws
    func indexSession(id: UUID) async throws
    func rebuildAll() async throws             // wipe every KnowledgeChunk, re-index all sources
    var events: AsyncStream<IndexingEvent> { get }
}

// Core/RAG/RAGPipeline.swift
enum AskResult: Sendable {
    case grounded(answer: String, sources: [SourceRef])   // SourceRef = Phase 1's Models/SourceRef.swift
    case notFound                                      // model returned the exact not-found sentence
    case retrievalOnly(passages: [RetrievedChunk], reason: RetrievalOnlyReason)
    case emptyIndex                                    // nothing indexed yet — friendly empty state
}
enum RetrievalOnlyReason: Sendable { case tierB(String), generationFailed, contextOverflow }
protocol RAGService: Sendable {
    func ask(_ question: String) async throws -> AskResult
}
```

Design decisions locked by these types:
- **Chunker is pure and sync** — no I/O, no actors — so the unit tests are trivial and fast.
- **One source-identity vocabulary, owned by Phase 1.** `TextChunk.sourceType`, `KnowledgeChunk.sourceTypeRaw`, `deleteChunks(sourceId:sourceType:)`, and `SourceRef.sourceType` all use the same shared `SourceType` enum; `AskResult.grounded` carries Phase 1's `SourceRef` unchanged, so persisted `ChatMessage.sourceRefsData` needs no new encoding. No RAG-local duplicates of either type may be introduced.
- **Two deliberate amendments to the spec §8 data model** (PLAN.md §8 as written has nowhere to put this data):
  1. `Document` gains `pageBreaks: [Int]` — the UTF-16 offset into `textContent` at which each page starts (element *i* is the start of page *i + 1*; page 1 starts at offset 0). Phase 6's PDF extraction must write it at import time. This is what lets `indexDocument(id:)` and `rebuildAll()` reconstruct page-numbered chunks from the stored `Document` alone — the original PDF is never kept, so without persisted breaks every rebuild would silently strip `pageNumber` and break the Phase 8 "tap opens the page" gate.
  2. `AppSettings` gains `embeddingDimension: Int?` (nil until first index). The spec's AppSettings fields (onboardingComplete, consentAcknowledged, preferredLocale, lastIndexRebuild) include no dimension slot; declare the field in Phase 1 if building from this plan, or add it as a lightweight migration in Phase 7.
- **`dimension` is read from the OS at runtime**, persisted into `AppSettings.embeddingDimension` on first index; a mismatch on load (OS update changed the model) forces a rebuild prompt rather than silently comparing incompatible vectors.
- **Indexing status lives in two places by design.** Documents use the persisted `Document.status` field the spec already defines. Sessions have **no persisted status field** (spec §8 `Session` carries none, and we add none): their `.indexing`/`.ready`/`.failed` state is ephemeral in-memory state published through `IndexerService.events`. `KnowledgeViewModel` derives session-row status from those events plus chunk presence — after a relaunch, a session whose chunks exist in the store renders as indexed, one with no chunks renders as unindexed until events report otherwise.
- **Not-found is detected by exact string match** on `"I couldn't find this in your saved knowledge."` after generation, so the UI can render a distinct card (no misleading source list under a non-answer).
- `RAGPipeline` calls `ModelGateway.respond` (Phase 5) — one fresh `LanguageModelSession` per call happens inside `FoundationModelService`; the pipeline never holds a session.

### 6.3 Algorithm specifics (what "done" means)

**TextChunker.** Tokenize into sentences with `NLTokenizer(unit: .sentence)`. Greedily append whole sentences until the chunk reaches ~200 words; start the next chunk with the trailing sentences of the previous one totaling ~40 words (effective stride ≈160 words). Never split mid-sentence, with one documented exception: a single sentence longer than 300 words (OCR junk, legalese) is hard-split on a word boundary and flagged in a comment/test. Documents: assign `pageNumber` from the page of the chunk's **first** sentence using the persisted `Document.pageBreaks` UTF-16 offsets (§6.2 amendment). Sessions: chunk over concatenated segment texts, carry `timestamp` = `startTime` of the first contributing segment. Empty/whitespace-only input → `[]`.

**NLContextualEmbeddingService.** `prepareAssets()` checks `hasAvailableAssets` and requests download if missing (first call may need network-free asset availability — assets ship on-device or via system download; surface progress state to the Knowledge tab if download is required). Per text: token embeddings → mean-pool across tokens → L2-normalize (zero-vector guard: if norm < ε, throw). Batch in groups of ~16 with `await Task.yield()` between batches. The whole service is an `actor` or runs on a background executor — **never on `@MainActor`** (CLAUDE.md hard rule). V1.1 escape hatch: if the manual retrieval eval (§6.6) disappoints, a converted MiniLM Core ML model slots in behind this same protocol — no call-site changes.

**VectorSearch.** Load candidate vectors, compute scores with `vDSP.dot` (or `vDSP_dotpr`) against the query; select top-K with a single pass + size-K min-heap (or full sort — at a few thousand candidates either is fine). Brute force **is the design**; do not build IVF/HNSW/etc. Target: < 100 ms for ~5,000 × 512-dim vectors on an iPhone 11-class device — expect single-digit milliseconds. To hit it, fetch `KnowledgeChunk.embedding` blobs once and unpack into a contiguous `[Float]` buffer; don't unpack inside the scoring loop.

**Indexer.** On trigger: delete any existing chunks for `sourceId` (re-index is idempotent, no duplicates), set status `.indexing`, chunk → embed (batched) → pack → insert `KnowledgeChunk` rows, set `.ready`; any thrown error → `.failed` with the error surfaced in the Knowledge row. "Set status" means the persisted `Document.status` for documents and the in-memory, event-published status for sessions (§6.2). `indexDocument(id:)` needs nothing beyond the stored `Document`: it chunks `textContent` against the persisted `pageBreaks`, so page numbers survive any re-index or rebuild without re-opening the source PDF (which is never stored). Runs as a structured background `Task` owned by the service, cancellation-safe: on cancel (source deleted mid-index, app teardown), delete partial chunks and restore previous status. `rebuildAll()` wipes all chunks, re-records `dimension` in `AppSettings.embeddingDimension`, then re-indexes every Document and Session sequentially with aggregate progress — page-numbered chunks come back identical because the breaks are persisted, not derived from the long-gone PDF.

**RAGPipeline (§3 budgets, non-negotiable).**
1. Fast path: zero chunks in store → `.emptyIndex` (skip embedding entirely).
2. Embed the question (single-element batch).
3. `VectorSearch.topK(k: 6)`.
4. `TokenBudgeter.pack`: instructions ≤ 250 tokens (template includes the grounding rule and the exact not-found sentence), question ≤ 250 (reject longer questions with a clear message before any model call), then add chunks in rank order while total input ≤ 2,800 and chunk budget ≤ 2,300 — typically 3 chunks survive. Reserve ~1,000 output tokens. Never hardcode 4,096: budgets flow through `TokenBudgeter`, which prefers `contextSize`/`tokenCount(for:)` and falls back to `ceil(chars/3.5)`.
5. Tier A: `ModelGateway.respond(...)`. Exact-match check → `.notFound` or `.grounded` with the `SourceRef`s of the packed chunks only (not all 6).
6. On `exceededContextWindowSize`: drop the lowest-ranked packed chunk, retry **once**; still failing → `.retrievalOnly(reason: .contextOverflow)`.
7. Tier B, or any generation error (guardrail refusal, model-not-ready, cancellation) → `.retrievalOnly` with the top passages. This is a first-class result, not an error screen.

**AskView/ViewModel.** Single default `conversationId` in V1. Send → append user `ChatMessage` → progress state ("Searching your knowledge…") → render result card → persist assistant `ChatMessage` with `sourceRefs`. Source snippet tap-through: `.document` → `DocumentDetailView` scrolled to `pageNumber`; `.session` → `SessionDetailView` scrolled to the segment nearest `timestamp`. History loads from storage on appear. Cancellation-safe when the view disappears mid-ask.

**DocumentDetailView.** New in Phase 8 — no earlier phase builds a document reader (Phase 6's Knowledge tab is list-only), and the "tap opens the page" gate is unmeetable without one. Init takes `(documentId: UUID, initialPageNumber: Int?)`. Loads the stored `Document`, splits `textContent` into pages at the persisted `pageBreaks` UTF-16 offsets (empty `pageBreaks` → one pseudo-page), and renders one row per page inside a `List`/`ScrollViewReader` — never one giant `Text`. On appear, `scrollTo(initialPageNumber, anchor: .top)`; a nil page (txt/md sources) lands at the top. Page rows carry a small "Page N" header so the user can confirm the citation. Also wire it as the Knowledge tab's document-row destination (one-line `NavigationLink` change in `KnowledgeView`) so documents aren't a dead end outside Ask.

### 6.4 Ordered build steps

Order chosen so every layer is testable before the next consumes it; steps 1–5 and 7–9 are Claude Code sessions, 6 and 10 are human-required.

1. **[CC]** `VectorPacking` + round-trip/malformed tests. Smallest unit, everything above stores through it.
2. **[CC]** `TextChunker` + boundary/overlap/metadata tests. Pure logic, zero OS dependencies — get it right in the simulator.
3. **[CC]** `EmbeddingService` protocol + `NLContextualEmbeddingService` + `VectorSearch` + cosine/top-K tests (search tests use synthetic vectors, no embedding needed).
4. **[CC]** `RAGIndexer` + wiring: import completion and session-stop triggers, Knowledge tab progress UI, Settings → Rebuild Index. `/build-check`.
5. **[CC]** Debug-only retrieval probe (temporary dev screen or debug button: type a query, see top-5 chunks + scores) — this is what makes step 6 possible before Ask exists.
6. **[HUMAN — device]** Phase 7 checkpoint on a physical iPhone: import a real 30-page PDF, watch `.indexing → .ready`, run "refund policy"-style queries through the probe, time the search (os_signpost or simple clock). Simulator cannot stand in for this: embedding asset availability/download and real search latency are device-only signals. **Commit Phase 7.**
7. **[CC]** `RAGPipeline` + `RAGPipelineTests` using a mock `ModelGateway` (scripted answers, scripted `exceededContextWindowSize` throws) and mock `EmbeddingService` — verifies packing math, the drop-retry-fallback ladder, and exact not-found detection with no device dependency.
8. **[CC]** Ask feature: `AskViewModel`, `AskView`, `AnswerCardView`, `SourceSnippetView`, `DocumentDetailView` (the `.document` tap-through target, §6.3) + the `KnowledgeView` row-navigation wiring, ChatMessage persistence, tap-through navigation, tier gating from Phase 5's `AvailabilityStatus`.
9. **[CC]** Failure-path polish: empty index, over-long question, retrieval-only card copy, cancellation on disappear. `/build-check`, review diff.
10. **[HUMAN — device]** Verify both tiers (§6.6), run the retrieval-quality eval, **commit Phase 8**.

No signing, entitlement, or App Store Connect work in these phases; the only human-blocking dependencies are physical devices and the Apple Intelligence toggle for the Tier B pass.

### 6.5 Edge cases and failure modes

- **Single sentence > chunk size** → hard word-boundary split (documented exception, unit-tested).
- **Empty/whitespace source, or a document that yields zero chunks** → status `.ready` with 0 chunks; Ask treats it as absent, no crash.
- **Embedding asset missing on first use** → `prepareAssets()` path with visible progress; failure → `.failed` status (persisted on `Document` for documents, in-memory via `events` for sessions) + retry affordance, never a spinner forever.
- **Preferred locale unsupported by NLContextualEmbedding** → fall back to English asset with an honest note in Settings; don't block indexing.
- **Zero-norm embedding** (degenerate input) → throw, skip that chunk, log; don't poison the index with NaNs.
- **Dimension mismatch** (`Data.count / 4 != stored dimension`) → `VectorPacking.unpack` throws; `VectorSearch` skips the row; Settings surfaces "index needs rebuilding."
- **Source deleted while indexing** → cancel the task, remove partial chunks (Phase 4's cascade must include chunks — verify, don't assume).
- **Rebuild tapped while an index task runs** → serialize: cancel in-flight work first, then rebuild.
- **Question longer than 250 tokens** → reject pre-flight with clear copy; never let it eat the chunk budget.
- **Model answers with a paraphrase of the not-found sentence** → exact-match check fails, answer renders as grounded; mitigate with instructions that quote the required sentence verbatim ("reply with exactly this sentence and nothing else").
- **Guardrail/safety refusal or model-not-ready mid-ask** → `.retrievalOnly(generationFailed)`; the user still gets passages.
- **App backgrounded mid-index** → indexing is not a background-audio activity; accept suspension, resume or restart idempotently on foreground (delete-then-reinsert makes this safe).

### 6.6 Testing — unit vs. device

**Unit (simulator, every `/build-check`):**
- Chunker: ~200-word target respected; ~40-word overlap present between consecutive chunks; no mid-sentence break (reconstruct sentences, assert containment); `chunkIndex` monotonic; `pageNumber` matches synthetic integer UTF-16 page-break offsets; `timestamp` = first segment's start; empty input → `[]`; giant-sentence hard split.
- VectorPacking: pack→unpack round-trip exact equality; unpack rejects wrong byte counts; little-endian byte layout asserted against a known vector.
- VectorSearch: cosine of two hand-computed 3-dim vectors matches to 1e-6; top-K returns correct ordering and scores on a crafted 10-vector set; K > candidate count returns all.
- RAGPipeline (mocks): packing keeps input ≤ 2,800 with 1,000 reserved; lowest-ranked chunk dropped first on overflow; retry happens exactly once then falls back; not-found exact match → `.notFound`; empty index short-circuits before embedding.
- ChatMessage persistence: sourceRefs survive a store round-trip.

**Device-only (simulators cannot validate these — plan real-iPhone time):**
- NLContextualEmbedding asset availability/download UX and real embedding output.
- Search latency on target hardware (< 100 ms over a few-thousand-chunk index; measure, don't assume).
- Foundation Models availability, real grounded-answer quality, guardrail behavior, and the Tier B pass (Apple Intelligence toggled off on a Tier A phone must yield retrieval-only cards with the correct reason).
- **Retrieval-quality manual eval (gate for the MiniLM decision):** index one real ~30-page PDF (e.g., a terms-of-service or employee handbook) plus 2 seeded meeting transcripts. Run 10 realistic queries ("what is the refund policy", "who owns the onboarding action item", …). For each, judge whether a relevant chunk appears in top-3. Record the score in the commit message. **≥ 7/10 relevant-in-top-3 = ship V1 as-is; below that, open the V1.1 MiniLM work item** — but do not block V1 on it, since the protocol swap is designed to be trivial.

### 6.7 Acceptance gate — commit checklist

Phase 7 commit (`feat(phase-7): chunking, embeddings, vector search`):
- [ ] All Phase 7 unit tests green; build clean, zero new warnings.
- [ ] 30-page PDF import on device reaches `.ready` with visible progress; chunk count sane (~1 chunk per ~160 words).
- [ ] "Refund policy"-style probe query returns visibly relevant top-5 with sensible scores.
- [ ] Search over the full index measured < 100 ms on device.
- [ ] Rebuild Index wipes and fully re-indexes; re-importing a document does not duplicate chunks; rebuilt document chunks retain correct `pageNumber` (from persisted `Document.pageBreaks`).
- [ ] Deleting a source removes its chunks (cascade verified).

Phase 8 commit (`feat(phase-8): ask (RAG)`):
- [ ] Question about seeded meeting content → grounded answer citing the correct session, tappable through to the right location.
- [ ] Question about a PDF fact → answer with page-numbered source; tap opens `DocumentDetailView` scrolled to that page.
- [ ] Absent-content question → exactly "I couldn't find this in your saved knowledge." rendered as the not-found card.
- [ ] Apple Intelligence off (Tier A phone): same questions → retrieval-only cards with honest reason copy; no error styling.
- [ ] Forced `exceededContextWindowSize` (debug hook or oversized chunks) exercises drop→retry→retrieval-only without a crash.
- [ ] Chat history with sourceRefs survives relaunch; airplane-mode full ask flow works (zero-network promise holds).
- [ ] All RAGPipeline unit tests green; no `LanguageModelSession` reuse anywhere (grep for session reuse in review).

### 6.8 Section-specific risks

| Risk | Mitigation |
|---|---|
| NLContextualEmbedding retrieval quality is mediocre for this workload | Protocol-first design + the §6.6 scored eval; MiniLM Core ML swap is a bounded V1.1 task, not a V1 blocker |
| Token estimation (`chars/3.5` fallback pre-26.4) undercounts → runtime overflow | The drop-retry-fallback ladder makes overflow non-fatal by construction; unit-test the ladder, and bias packing 5–10% under budget when only the estimator is available |
| Model ignores the exact not-found phrasing | Verbatim-sentence instruction + exact-match post-check; worst case degrades to a grounded-looking answer, never a crash |
| Indexing large PDFs blocks or bloats memory | Batch embedding (~16 texts) with yields; measure on the 30-page PDF at the Phase 7 gate |
| Index/source drift (crash mid-index, OS embedding model change) | Idempotent delete-then-reinsert per source; dimension recorded in `AppSettings.embeddingDimension` with mismatch → rebuild prompt; Rebuild Index as the universal repair tool (safe for page numbers — rebuilds chunk from persisted `Document.pageBreaks`, never the discarded PDF) |
| Ask feels dead on Tier B and reviewers judge it broken | Retrieval-only card designed as a real feature (title, passages, sources) and exercised in the manual test matrix (§9 rows 7–8) |

---

## 7. Phases 9–10, Test Matrix, Schedule & Risk Register

This section covers the last two build phases (privacy/settings, hardening), the pre-TestFlight manual gate, the master schedule across all phases, and the ranked risk register. Authority for budgets, tiers, and data model: PLAN.md §2, §3, §8. Nothing here relaxes the hard constraints: 4,096-token context, iOS 26.0 floor, zero third-party packages, zero network calls, one fresh `LanguageModelSession` per call, never touch the `.xcodeproj`.

### 7.1 Phase 9 — Settings, privacy posture, data controls

All Claude Code work except where marked. Depends on Phase 5 (model status), Phase 7 (Rebuild Index), and Phase 4 (session export format reuse).

**Files to create/replace:**

| Path | Purpose |
|---|---|
| `Features/Settings/SettingsView.swift` | Replaces Phase 1 placeholder: model status, storage, transcription locale, consent reminder, rebuild, export, delete |
| `Features/Settings/SettingsViewModel.swift` | `@MainActor @Observable`; owns all Settings state |
| `Features/Settings/DeleteAllDataView.swift` | Type-to-confirm sheet (user must type `DELETE`) |
| `Core/Storage/StorageUsageService.swift` | Protocol + SwiftData impl computing real byte counts |
| `Core/Storage/DataExportService.swift` | Protocol + impl building share-sheet payload |
| `Core/Storage/DataWipeService.swift` | Protocol + impl for the full wipe |
| `Models/StorageUsage.swift` | Pure value type |
| `EchoMindTests/NetworkAuditTests.swift` | Zero-network regression guard (§7.2) |
| `network-allowlist.txt` (repo root) | Starts **empty**; one relative path per line |

**Key signatures (pin the design):**

```swift
struct StorageUsage: Sendable {
    let sessionsBytes: Int64    // segments + stored summaries
    let documentsBytes: Int64   // extracted text
    let indexBytes: Int64       // chunk text + packed embeddings
    var totalBytes: Int64 { sessionsBytes + documentsBytes + indexBytes }
}

protocol StorageUsageService: Sendable {
    func usage() async throws -> StorageUsage
}

protocol DataExportService: Sendable {
    /// One Markdown file per session (title, date, duration, timestamped
    /// transcript, summary if present) + documents-list.md manifest.
    /// Files land in a temp export dir; caller hands [URL] to ShareLink
    /// as multiple items and deletes the dir afterward.
    func exportAll() async throws -> [URL]
}

protocol DataWipeService: Sendable {
    /// Sessions, segments, documents, chunks (index), chat messages;
    /// resets AppSettings except onboardingComplete/consentAcknowledged.
    func deleteAllData() async throws
}
```

**Behavior requirements:**

- **Model status row** renders `FoundationModelService.AvailabilityStatus` (Phase 5) with the *specific* reason: Tier A; Tier B / device not eligible; Tier B / Apple Intelligence not enabled → show the hint "Enable Apple Intelligence in iOS Settings"; Tier B / model not ready → "downloading, try again later". Refresh on `scenePhase == .active` so toggling Apple Intelligence in iOS Settings is reflected when the user returns.
- **Preferred transcription locale row** — the destination of audio-speech.md §3.6's locale-unsupported hint (without this row that error is a dead end): a Picker over `SpeechTranscriber.supportedLocales` that reads/writes `AppSettings.preferredLocale` through `AppSettingsStore`. Default selection is the device locale; a change applies from the *next* session start (never rebinds an in-flight transcriber) and may trigger the Phase 3 asset-download progress UI for the new locale.
- **Storage usage** must be computed from real data (sum `utf8.count` of texts + `embedding.count` of chunk Data), not `FileManager` guesses against the whole store. Compute off the main actor; cache per appearance.
- **Rebuild Index** reuses the Phase 7 Indexer wipe-and-reindex path, with progress and cancellation; disable the button while indexing.
- **Delete All Data** button is `.destructive`, requires the typed confirmation, and after the wipe the app must be indistinguishable from fresh-install *except* onboarding/consent flags (matrix row 11 checks "app equals fresh install" for content; re-running onboarding is not required).
- Recording-consent reminder uses the exact onboarding copy — single source of truth: put the string in one place (e.g. `Models/ConsentCopy.swift`) referenced by both.
- **Error-copy sweep** (spec Phase 9 item 3): review every user-facing error string added in Phases 1–8 (mic/speech denied, locale unsupported, asset download failed, scanned-PDF rejection, size cap, context-overflow fallback, low storage) for tone and accuracy — plain, honest, actionable; no raw error codes or jargon.

### 7.2 The zero-network audit test (regression guard)

This is the enforcement mechanism for the V1 privacy promise and the App Privacy "data not collected" declaration. It scans app sources at test time and fails on any networking API outside the allowlist (which ships empty).

```swift
final class NetworkAuditTests: XCTestCase {
    // Substring match, deliberately strict: even a comment mentioning
    // URLSession fails. Keep the source clean instead of the test clever.
    private static let forbidden = [
        "URLSession", "URLRequest", "NSURLConnection", "CFNetwork",
        "import Network", "NWConnection", "NWListener", "NWBrowser",
        "SCNetworkReachability", "MultipeerConnectivity",
    ]

    func testZeroNetworkAPIs() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)   // .../EchoMindTests/NetworkAuditTests.swift
            .deletingLastPathComponent()                  // EchoMindTests/
            .deletingLastPathComponent()                  // repo root
        let sourceRoot = repoRoot.appendingPathComponent("EchoMind") // app target only
        let allowlist = Set(
            (try? String(contentsOf: repoRoot.appendingPathComponent("network-allowlist.txt"), encoding: .utf8))?
                .split(separator: "\n").map(String.init) ?? []
        )

        var violations: [String] = []
        for file in try swiftFiles(under: sourceRoot) {
            let relative = String(file.path.dropFirst(repoRoot.path.count + 1))
            guard !allowlist.contains(relative) else { continue }
            let lines = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
            for (i, line) in lines.enumerated() {
                for token in Self.forbidden where line.contains(token) {
                    violations.append("\(relative):\(i + 1): '\(token)'")
                }
            }
        }
        XCTAssertTrue(violations.isEmpty,
            "Zero-network promise violated:\n" + violations.joined(separator: "\n"))
    }

    private func swiftFiles(under root: URL) throws -> [URL] {
        var result: [URL] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            // Filter INSIDE the body — a condition on the `while` line would
            // terminate enumeration at the first non-.swift entry and make
            // the audit pass vacuously.
            guard url.pathExtension == "swift" else { continue }
            result.append(url)
        }
        return result
    }
}
```

Notes: `#filePath` resolves on the build Mac, so this works under `xcodebuild test` with no configuration. It scans only the app target folder (test sources may legitimately name the forbidden strings). **Prove the guard works before committing:** temporarily add `let s = URLSession.shared` to any app file, confirm the test fails with the right file:line, revert. That negative test is part of the Phase 9 acceptance gate.

### 7.3 Phase 10 — Hardening pass

All Claude Code work except where noted; ordered:

1. **Full test suite green** (unit tests from Phases 2, 5, 7 + network audit). Fix, don't skip.
2. **Cancellation audit.** Every view-scoped async operation runs in `.task {}` (auto-cancelled on disappear) or is explicitly cancelled in `onDisappear`. Services must observe cancellation: `try Task.checkCancellation()` between map-reduce windows in Summarizer, between batches in Indexer, before the model call in RAGPipeline. **Deliberate exception:** recording/transcription is *not* cancelled on view disappearance — background capture is a core feature; its lifetime belongs to `AudioEngineManager`/app scope, only Stop or an unrecoverable interruption ends it. Write this down in a comment; a well-meaning future cleanup that ties recording to view lifetime is the most likely regression.
3. **Low-storage graceful failure.** Preflight before recording start and document import (warn below ~200 MB via `volumeAvailableCapacityForImportantUsageKey`); catch SwiftData save throws and surface "Not enough storage to save — free up space and try again" rather than crashing. Never lose already-persisted segments.
4. **Accessibility.** `accessibilityLabel` on every icon-only control (record, stop, import, send); transcript and answer views use relative text styles so Dynamic Type works — verify at the largest accessibility size (AX5) that nothing truncates; VoiceOver announces recording start/stop state changes.
5. **Empty states** for Home (no sessions), Sessions, Knowledge, Ask (no chats) — friendly one-liner + the primary CTA, not a blank list. New shared component: `Features/Common/EmptyStateView.swift`.
6. **App icon + launch screen.** Placeholder icon into `Assets.xcassets` (asset catalog edits are safe — not the pbxproj). The launch screen is the `UILaunchScreen` key (solid color + icon, no storyboard) — but with the spec-mandated template setup (spec §1, §4.3: synchronized folder groups, no standalone Info.plist) that key is generated from `INFOPLIST_KEY_*` build settings stored inside the `.xcodeproj`, which Claude Code must never touch. Setting it is therefore a **human** step — see §7.4 item 4.

### 7.4 Human-only ship steps (Claude Code cannot do these)

1. App Store Connect: create the app record (bundle ID must match Xcode).
2. App Privacy: declare **data not collected** — true in V1 and defensible because of §7.2.
3. Export compliance: uses only standard OS encryption → set `ITSAppUsesNonExemptEncryption = NO` in the Info tab (this one plist key is human work since it's a legal declaration).
4. Launch screen: add the `UILaunchScreen` key in the target's Info tab (solid background color + app icon, no storyboard). With the template's generated Info.plist there is no plist *file* — the key lives in the `.xcodeproj` as a build setting, so this one-row edit is human work, same as #3. (Claude Code supplies the icon asset in §7.3 item 6.)
5. Xcode: Product → Archive on the release scheme; validate; upload.
6. TestFlight: add internal testers; write "What to Test" notes pointing at the matrix rows below; include a reviewer note explaining the consent flow and that recording is user-initiated only (pre-empts App Review questions on recording apps).

### 7.5 Manual test matrix — the pre-TestFlight gate

Run the full 12-row matrix (PLAN.md §9) **after Phase 10 lands and before every archive/upload — no exceptions**, on a physical Tier A device plus a Tier B device (or Tier A with Apple Intelligence off) for rows 7–8. None of these are simulator-valid: the simulator cannot exercise real mic capture quality, background-audio continuation, phone-call interruptions, Foundation Models availability, battery, or true latency.

| # | Test | Pass condition |
|---|---|---|
| 1 | 60-minute continuous session | No stall; segments persisted throughout; summary succeeds |
| 2 | Lock screen at minute 2, unlock at minute 10 | Capture + transcription continuous; UI catches up |
| 3 | Incoming phone call mid-session | Pauses, resumes after call, state visible |
| 4 | AirPods connect and disconnect mid-session | No crash; capture continues on active input |
| 5 | Force-quit mid-recording | All finalized segments present on relaunch |
| 6 | Airplane mode, fresh boot, full flow | Record → summary → ask all work offline (Tier A) |
| 7 | Tier B device full pass | Transcription + retrieval-only everywhere; honest messaging |
| 8 | Apple Intelligence toggled off on Tier A | App degrades to Tier B behavior with correct reason |
| 9 | 30-page PDF import + ask | Indexed; grounded answers with page sources |
| 10 | Battery: 1-hour session from 100% | Note drain %; investigate if extreme |
| 11 | Delete all data | Content equals fresh install: zero sessions/segments/documents/chunks/chats, storage counts zero, index gone; onboarding/consent flags intentionally persist (see note below) |
| 12 | Locale asset not yet downloaded (fresh device) | Progress UI, then transcription works |

Rows 1 and 10 are 60+ minutes each, but one physical session covers both (start the row-1 hour from 100% battery and record the drain for row 10), so the first pass costs Day 12 about one extra hour — "no exceptions" holds for the first upload too. The *repeat* passes (at least three each) belong to the soak weeks (§7.6). Row 12 needs a device that has never downloaded the locale asset (or Settings → wipe of downloaded assets); rows 7/8 need the human to toggle Apple Intelligence in iOS Settings.

Row 11 deliberately amends PLAN.md §9's literal "App equals fresh install": per §7.1, `DataWipeService` preserves `onboardingComplete`/`consentAcknowledged`, so post-wipe the app does **not** re-show onboarding — a product decision, not a bug. Test content-equality only, and record the row in `TESTLOG.md` as "content equals fresh install; onboarding flags preserved by design" so a literal reading of the spec matrix doesn't fail the app.

### 7.6 Master schedule

**Phase dependency graph** (arrows = strictly blocks):

```
P0 Xcode/project setup (human)
 └─► P1 skeleton/storage/onboarding
      ├─► P2 audio ─► P3 live transcription ─► P4 sessions
      │                                          ├─► P5 AI core (gateway, budgeter, summaries)
      │                                          └─► P6 document import
      │                                               └─► P7 chunk/embed/search  ◄─ (needs P3/P4 for session indexing)
      │                                                     └─► P8 Ask (RAG) ◄─ also needs P5 (ModelGateway)
      └───────────────────────────────────────────────────────────► P9 settings/privacy ◄─ needs P5 (status), P7 (rebuild), P4 (export)
                                                                      └─► P10 hardening ─► matrix ─► TestFlight
```

Real parallelism: **P5 and P6 are independent of each other** — both only need P4; run them in either order or interleave. P7 needs P6 (documents) but *not* P5. P8 is the join point (P5 + P7). Everything else is a strict chain. If a second pair of hands existed, P5 and P6+P7 are the split; solo, the ordering below is optimal because P7 (flagged risky) gets started earliest.

**Day-by-day (12 focused days, within the spec's 10–14):**

| Day | Work | Owner | Gate before next day |
|---|---|---|---|
| 0 | Upgrade Xcode 16.4 → 26.x and `sudo xcode-select -s /Applications/Xcode.app` (this Mac: macOS 15.5, M4, 16 GB — **disk resolved 2026-07-06: 73.9 GB free after deleting Docker's 35 GB VM disk; no longer a blocker**), Developer Program, create project (synchronized folder groups, iOS 26.0 min), Background Modes → Audio, usage strings, **add the Data Protection capability and edit the `.entitlements` value to `NSFileProtectionCompleteUnlessOpen`** (Xcode's toggle defaults to `...Complete`), **confirm a unit-test target exists** (adding targets edits the pbxproj → human-only; foundation.md §2.10 step 0), run empty app on device, Claude Code + git init | Human | Empty app runs signed on a physical iPhone; Data Protection entitlement set to `CompleteUnlessOpen` and unit-test target present — P1 is blocked otherwise |
| 1 | P1 skeleton, SwiftData models, onboarding + consent | CC | Build clean; onboarding shows once; commit `feat(phase-1)` |
| 2 | P2 audio engine + interruptions + background | CC + human device test | Lock-screen and phone-call tests pass on device; commit |
| 3 | P3 live transcription | CC + human device test | Partials <1 s; incremental persistence verified; commit |
| 4 | P3 device shakeout: long dictation, lock, force-quit, AirPods (buffer day the spec tells us to protect) | Human + CC fixes | Matrix rows 2–5 pass informally; commit |
| 5 | P4 sessions list/detail/export + real Home | CC | Rename/delete/search/export work; no orphans; commit |
| 6 | P5 AI core: ModelGateway, TokenBudgeter, Summarizer, summary UI | CC + human device test | 9,000-word fixture summarizes with zero context errors on device; Tier B state correct; commit |
| 7 | P6 document import; start P7 chunker + tests | CC | PDF/md import + scanned-PDF rejection; commit P6 |
| 8 | P7 embeddings, packing, Indexer, VectorSearch + unit tests | CC | Unit tests green; commit |
| 9 | P7 retrieval-quality day on device: 30-page PDF, golden queries, <100 ms search (second protected buffer) | Human + CC | "Refund policy"-style queries return relevant top-5; decide now if MiniLM fallback must be pulled into V1.1 planning; commit |
| 10 | P8 Ask end-to-end, both tiers | CC + human | Grounded answer w/ sources; exact not-found sentence; retrieval-only on Tier B; commit |
| 11 | P9 settings, export/wipe, network-audit test (incl. negative test), error-copy sweep | CC | Audit test fails on injected URLSession, passes clean; delete-all verified; error copy swept; commit |
| 12 | P10 hardening + human ship steps (§7.4) + full matrix run (rows 1/10 combined into one 60-min session per §7.5 — budget the extra hour) | CC + human | All 12 rows pass → archive → upload → internal TestFlight |

**Calendar reality (4–6 weeks to a credible TestFlight):** the 12 build days occupy weeks 1–3 at real-life pace. Weeks 3–6 are **soak time, not idle time**: use EchoMind for actual meetings daily; run matrix rows 1 and 10 at least three times each across the soak window (on top of the Day-12 first pass); file and fix issues in short Claude Code sessions (one bug per session, `/clear` between); re-run the full matrix before every new TestFlight build. Commit gates are non-negotiable: no phase starts until the previous phase's gate row is green and committed — reverting a phase must always be one `git revert` away.

### 7.7 Risk register (ranked)

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| 1 | Audio/interruption edge cases — calls, AirPods, media-services reset, lock screen (spec flags Phases 2–3 as the schedule risk) | High | High | Two protected device-test days (days 2, 4); interruption handling is explicit Phase 2 scope; incremental segment persistence caps data loss at the volatile tail; matrix rows 2–5 re-run every build |
| 2 | 4K-context overflow on real meetings (fixtures behave, humans ramble) | High | High | Every call through TokenBudgeter; map-reduce with re-split retry; RAG drop-lowest-chunk retry then retrieval-only fallback; soak-week rule: every real 60-min meeting that summarizes cleanly is a test pass, every overflow is a P1 bug |
| 3 | NLContextualEmbedding retrieval quality disappoints (spec flags Phase 7) | Medium | High | Day 9 golden-query eval on a real PDF before building Ask on top; `EmbeddingService` protocol makes the Core ML MiniLM swap a V1.1 drop-in; retrieval-only UX is first-class so weak generation grounding still ships |
| 4 | **Toolchain not yet iOS-26-capable.** macOS updated to **15.7.7** (✅ meets the 15.6 minimum for Xcode 26.0–26.3; 26.4+ would need Tahoe 26.2). Xcode 16.4 (iOS 18.5 SDK only) is still the only Xcode installed, and `xcode-select` points at CommandLineTools. Disk is no longer a factor (73.9 GB free after Docker VM deletion). | Medium | High (hard blocker) | Remaining Day-0 work: install **Xcode 26.3** (App Store, newest on Sequoia, iOS 26.2 SDK), then `sudo xcode-select -s` to it, accept license, `xcodebuild -downloadPlatform iOS`. **Pin this Xcode/OS combo until after TestFlight** — do not upgrade to Tahoe/Xcode 26.4+ mid-project, and don't let test-device iOS versions outrun the installed SDK. |
| 5 | Apple Intelligence availability variance across test devices (eligible-but-disabled, model-not-ready after reboot/language change) | Medium | Medium | Runtime tier from `SystemLanguageModel.default.availability` with per-reason handling (PLAN.md §2); Settings shows the exact reason + enable hint; matrix rows 7–8 on every build; never cache tier across launches |
| 6 | App Review scrutiny on recording apps (consent, ambient recording concerns) | Medium | Medium | Onboarding consent notice + persistent in-app recording indicator + no always-listening (user-initiated only); honest mic/speech permission strings; data-not-collected label backed by the §7.2 audit test; reviewer notes in TestFlight/submission explaining all of the above |
| 7 | Battery drain on 60-min sessions triggers user complaints or thermal throttling of transcription | Medium | Medium | Matrix row 10 with recorded drain % across soak weeks; all audio/speech/embedding off the main thread (CLAUDE.md rule); if extreme: profile with Instruments on device (human), check buffer-tap format conversions and UI re-render frequency first |
| 8 | SwiftData write contention/corruption with background writes while locked | Low | High | `.completeUnlessOpen` file protection set in Phase 1 (spec-mandated); force-quit matrix row 5 every build; incremental saves are small and serialized through repositories |

### 7.8 V1.1 forward pointer

Per PLAN.md §10: when iOS 27 ships, add a `PCCModelGateway` behind the *existing* `ModelGateway` protocol (32K context makes most summaries single-shot; keep map-reduce as the offline route). Cloud is strictly opt-in and **default off**, with per-request routing visible in Settings; the App Privacy label and the network-audit allowlist are updated in the same PR that ships any cloud path — the §7.2 test failing is the designed tripwire that forces that conversation. Other V1.1 candidates in spec order: MiniLM embeddings, speaker labels, DOCX import, cross-session search, PDF export.

### 7.9 Acceptance gate — the ship commit

Check every box before `git tag v1.0-tf1` and upload:

- [ ] Settings shows real model status (correct tier + specific reason + enable hint), real storage byte counts, working preferred-transcription-locale picker (persists to `AppSettings.preferredLocale`), consent reminder, working Rebuild Index
- [ ] Export All Data produces per-session Markdown + document list via share sheet; files open correctly in Files/Notes
- [ ] Delete All Data (type-to-confirm) leaves the app content-equal to a fresh install, index included
- [ ] `NetworkAuditTests` passes — and demonstrably failed when a `URLSession` reference was injected (negative test performed and reverted)
- [ ] Full unit-test suite green via `xcodebuild test`
- [ ] Cancellation audit done; recording explicitly exempt and commented as such
- [ ] Low-storage paths fail with readable messages, no data loss of persisted segments
- [ ] All user-facing error copy swept for tone and accuracy (spec Phase 9 item 3)
- [ ] Accessibility: labeled controls; transcript + answer views legible at AX5 Dynamic Type
- [ ] Empty states on all tabs; app icon + launch screen present
- [ ] All 12 matrix rows passed on physical devices (Tier A + Tier B/AI-off), dated and noted in the repo (`TESTLOG.md`)
- [ ] App Store Connect record, data-not-collected privacy label, export-compliance answer done (human)
- [ ] Archive validated, uploaded, internal testers invited (human)

---
