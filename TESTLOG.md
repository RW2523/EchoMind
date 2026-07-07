# EchoMind — Manual Test Log

Run the full matrix (BUILD_PLAN.md §7.5 / PLAN.md §9) **before every archive/upload**,
on a physical Tier A iPhone (Apple Intelligence on) plus a Tier B device (or Tier A
with Apple Intelligence off) for rows 7–8. None of these are simulator-valid.

Record date, device, OS, and pass/fail per row.

| # | Test | Pass condition | Result |
|---|---|---|---|
| 1 | 60-minute continuous session | No stall; segments persisted throughout; summary succeeds | |
| 2 | Lock at minute 2, unlock at minute 10 | Capture + transcription continuous; UI catches up | |
| 3 | Incoming phone call mid-session | Pauses, resumes after call, state visible; timer excludes the call | |
| 4 | AirPods connect + disconnect mid-session | No crash; capture continues on active input | |
| 5 | Force-quit mid-recording | All finalized segments present on relaunch (only volatile tail lost) | |
| 6 | Airplane mode, fresh boot, full flow | Record → summary → ask all work offline (Tier A) | |
| 7 | Tier B device full pass | Transcription + retrieval-only everywhere; honest messaging | |
| 8 | Apple Intelligence toggled off on Tier A | Degrades to Tier B with the *not-enabled* reason; back on → returns to Tier A | |
| 9 | 30-page PDF import + ask | Indexed to .ready; grounded answers with page sources; tap opens the page | |
| 10 | Battery: 1-hour session from 100% | Note drain %; investigate if extreme (combine with row 1) | |
| 11 | Delete all data | Content equals fresh install (0 sessions/segments/documents/chunks/chats, storage 0); onboarding/consent flags persist **by design** | |
| 12 | Locale asset not yet downloaded (fresh device) | Progress UI, then transcription works | |

**Retrieval-quality eval (gates the MiniLM decision, §6.6):** index one real ~30-page
PDF + 2 seeded transcripts; run 10 realistic queries; judge relevant-in-top-3.
Score: __ / 10. (≥ 7 → ship NLContextualEmbedding as-is; below → open V1.1 MiniLM item.)
