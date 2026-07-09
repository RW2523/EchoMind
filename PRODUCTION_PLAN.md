# EchoMind 1.0 — Production & App Store Submission Plan

Goal: ship a **top-grade, App-Store-approved 1.0**. Strategy in one line:
**1.0 ships with ZERO third-party packages** — Apple Intelligence + NLEmbedding +
SpeechTranscriber cover every headline feature (record → transcribe → auto-report
→ smart groups → memory → chat/voice ask), all proven working. The package-gated
extras (local Qwen, EmbeddingGemma, Kokoro, diarization, sqlite-vec) become the
**1.1 "Pro brains" update** — they're already code-complete behind `#if canImport`.
This removes every third-party review risk from 1.0 and keeps the App Privacy
story perfect: **"Data Not Collected."**

## 0. Readiness audit (done — actual state of the repo)

| Item | State |
|---|---|
| Mic + Speech usage descriptions (privacy-first copy) | ✅ present |
| Launch screen key, background-audio mode, orientations | ✅ present |
| Bundle id `com.ajace.EchoMind`, v1.0 (build 1), icon 1024px | ✅ present |
| 261 tests green; zero-network audit test | ✅ passing |
| RAG + generation verified live (simulator, tierA) | ✅ verified |
| **PrivacyInfo.xcprivacy** | ❌ **missing — blocker** (UserDefaults → CA92.1; file timestamps/size → C617.1) |
| Device validation (mic/speech/voice/reports on real iPhone) | ❌ **not done — biggest risk** |
| App Store Connect record, signing, screenshots, metadata | ❌ not started |
| Package-gated UI (Model Manager rows) visible without engines | ⚠️ hide for 1.0 (reviewer confusion) |

## 1. Workstreams

### A — Code finalization for 1.0 (me; ~1 day)
1. **PrivacyInfo.xcprivacy** — declare required-reason APIs (UserDefaults CA92.1,
   file timestamp/disk-space C617.1/E174.1 as applicable), *no* tracking, *no*
   collected data types. This is a review blocker; do it first.
2. **1.0 feature gating** — hide package-dependent UI when engines aren't linked:
   AI-Models chat/embedding/voice download rows (keep the screen: Apple
   Intelligence status + Memory link), "engine not installed" warnings gone.
   One `#if canImport`-driven flag; 1.1 un-hides automatically.
3. **About / legal screen** — version, "100% on-device / no data collected"
   statement, licenses placeholder (fills in 1.1 with MLX/Gemma attributions).
4. **Review-proofing pass** — every failure path shows friendly copy (Tier B
   devices, denied permissions, empty states); confirm no debug UI ships in
   Release (`#if DEBUG` audit); Release-configuration build + full suite.
5. **Version/infra** — deployment target sanity (26.x — device floor is "iPhone
   with Apple Intelligence"; state it in metadata), archive builds clean.

### B — Device validation matrix (YOU + me; 2–3 days; the critical gap)
Run on a physical iPhone (Apple Intelligence on). I provide the checklist +
in-app diagnostics; you run and report; I fix same-day.
1. **Core loop ×3 real meetings**: record → live transcript → stop → auto-report
   (summary/actions correct?) → category appears → memory facts appear → ask a
   question about the meeting (grounded) → tap-to-play audio seek.
2. **Voice agent**: push-to-talk; streaming sentence-by-sentence latency (target
   first audio ≤ 2.4 s, kill 3.5 s); hands-free 10-turn; barge-in with volume up
   (no self-transcription).
3. **Torture**: 60–90 min recording (thermals/battery note), backgrounded
   recording, interruption (phone call), locked-phone recording, storage wipe,
   permission-denied → Settings deep-link, airplane mode everything-works.
4. **Matrix rows recorded in TESTLOG.md**; each failure becomes a fix commit.
   **Gate: core loop 3/3 clean before submission.**

### C — App Store Connect & compliance (YOU, with my copy; ~½ day)
1. Apple Developer Program account; App ID + signing (Xcode-managed).
2. App Store Connect record: name **EchoMind** (check availability; fallbacks
   ready), primary category **Productivity** (secondary Business), age 4+.
3. **App Privacy questionnaire: "Data Not Collected"** (true and provable — our
   audit test enforces it). No tracking. No third-party SDKs.
4. Export compliance: standard encryption only → exempt; add
   `ITSAppUsesNonExemptEncryption = NO` (I'll add the key).
5. Review notes (I draft): explain on-device AI (FoundationModels), that mic +
   speech permissions are core, requires Apple-Intelligence-capable device, and
   include a 60-second reviewer walkthrough script + a bundled sample document so
   reviewers can test Ask without recording a meeting.

### D — Assets & metadata (me drafts, you approve; ~1 day)
1. **Screenshots** (6.9" + 6.5", from simulator with seeded demo data): Home
   status, live transcript, auto-report with actions, grouped sessions, Ask chat,
   memory screen. Framed + captioned.
2. **App icon** — current 1024 works; optional: regenerate to match the navy/blue
   brand (I can produce programmatically; a designer pass is better but not
   blocking).
3. **Copy**: subtitle ("Private AI meeting memory"), description (privacy-first
   angle: *"Your meetings, remembered. Nothing leaves your iPhone."*), keywords,
   promo text, support URL + privacy-policy URL (one-pager; I draft — required
   even for no-data apps).

### E — Beta & soak (YOU + me; 3–5 days parallel)
1. TestFlight internal build; you + 2–5 real users, real meetings.
2. Soak checks: SwiftData store growth, audio storage sizes, report quality on
   *real* speech (prompt tuning pass if summaries disappoint — likeliest fix area),
   crash-free sessions (MetricKit only; no analytics SDK).
3. One RC build after fixes → 48 h quiet soak → submit.

### F — Submission & review (YOU; ~1 h + Apple's queue)
Archive → upload → attach metadata/screenshots → submit with review notes.
Likely review friction, pre-answered: AI-generated content (4.1/1.2 — outputs are
private summaries of the user's own speech, not shared content, no moderation
surface); mic in background (declared audio mode, core function); device
requirement (stated in description + review notes).

## 2. Sequence & effort

```
A code-final (me, 1d) ──►  B device matrix (you+me, 2–3d) ──► fixes (me)
D assets (me, 1d, parallel)      C ASC setup (you, ½d, parallel)
                    └────► E TestFlight soak (3–5d) ──► F submit
```
**~7–10 calendar days to submission**, dominated by device validation + soak.

## 3. Definition of "top grade" (release gates)

- [ ] PrivacyInfo.xcprivacy present; Release archive validates in Organizer
- [ ] 261+ tests green in Release configuration
- [ ] Device matrix: core loop 3/3, voice latency ≤ 3.5 s or push-to-talk-only ship
- [ ] Zero crashes across soak; interruption/background/lock recording clean
- [ ] Every screen: empty state + failure copy + Dynamic Type XL + VoiceOver labels
      on interactive elements + Reduce Motion (already honored) spot-check
- [ ] App Privacy = Data Not Collected; privacy policy URL live
- [ ] Screenshots/metadata approved by you; reviewer walkthrough included
- [ ] 1.1 branch plan intact (packages) — nothing in 1.0 blocks it

## 4. Post-1.0 roadmap (already built, gated)
1.1 "Own the model": MLX Qwen + EmbeddingGemma + Model Manager unhidden (needs
your package add + device eval). 1.2: Kokoro voice + diarization spike. 1.3:
Live Activities/widgets (needs extension target), Siri/App Intents.

## 5. Honest risks

| Risk | Mitigation |
|---|---|
| Real-speech report quality underwhelms | TestFlight prompt-tuning pass is *expected*, budgeted in E |
| Apple Intelligence device floor shrinks audience | Positioned as premium requirement in metadata; 1.1 local LLM removes the floor |
| "EchoMind" name taken in ASC | Check day 1; fallbacks: "EchoMind — Meeting Memory", "EchoMinder" |
| Voice latency misses on device | Kill-criterion: ship push-to-talk only, hands-free behind a setting |
| Review rejects background audio | Recording is user-initiated, indicator visible, core function — precedent is strong (voice memos category) |
