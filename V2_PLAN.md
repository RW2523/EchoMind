# EchoMind V2 — Conversational RAG, Portable Models, Signature Features & UI Overhaul

**Status:** planning · **Baseline:** V1 complete (10 phases, 113 tests, commit `dabe3d7`)
**Thesis:** V1 proved the private, on-device pipeline. V2 makes it feel like a product people
show other people: a real conversational assistant over your own knowledge, AI that works on
*every* iPhone (not just Apple Intelligence devices), features nobody else has on-device, and
a UI that looks like it belongs in an Apple keynote.

How to execute: same discipline as V1 — one phase per session, build + test at every step,
commit at green gates, device-verify what the simulator can't. Phases continue V1's numbering
(11–22), grouped into four shippable milestones (V2.0 → V2.3).

---

## 0. Why V2, in one table

| V1 reality | V2 goal |
|---|---|
| Ask answers one question at a time; strict grounding | A true chat: multi-turn memory, follow-ups, streaming answers |
| AI only on Apple Intelligence devices (Tier B = passages only) | **Full AI on every iOS 26 iPhone** via a bundled local LLM |
| Embeddings fail in the simulator; quality unmeasured | MiniLM Core ML: works everywhere, quality-eval'd, upgrade path |
| Recording UI is functional but flat | Live waveform, Dynamic Island, glass design language |
| Transcript is text-only, discarded audio | Opt-in audio retention with tap-to-play sync |
| No presence outside the app | Siri, widgets, Spotlight, Live Activities, Reminders hand-off |

---

## 1. Decision gates — sign off before building

V1's hard rules were "zero third-party packages, zero network calls." V2 deliberately amends
both. Each amendment is scoped, opt-in, and keeps the privacy story intact — but they are
product decisions, not engineering ones. **Confirm these four before Phase 11:**

| # | Decision | Recommendation | Why |
|---|---|---|---|
| G1 | **Relax "zero third-party packages"?** Local LLM (llama.cpp or MLX-Swift) and optional WhisperKit/FluidAudio require Swift packages. | **Yes, allowlisted.** A named, pinned list (`PACKAGES.md`): inference engines only, no analytics, no networking SDKs. | There is no first-party way to run a non-Apple LLM. The rule's *intent* (no data leaves, no supply-chain surprises) survives via the allowlist + the network audit test. |
| G2 | **How do models reach the phone?** Bundling 1–2 GB in the app vs. in-app download. | **Hybrid.** Bundle the small MiniLM embedder (~25 MB, INT8). Download the LLM (0.7–1.2 GB) via an in-app Model Manager with an explicit consent screen. | A 2 GB App Store binary kills installs. Downloads are the industry norm (Whisper apps, local-LLM apps). This adds the **first network-allowlist entry** — download-only, pinned host, checksum-verified, nothing ever uploaded. App Privacy stays *Data Not Collected*. |
| G3 | **Retain recorded audio?** V1 discards audio after transcription. | **Opt-in, default off.** Per-session toggle; audio counted in storage usage; wiped by Delete All. | Tap-a-segment-to-hear-it is a top-tier feature, but audio retention changes the privacy posture and storage footprint — the user must choose it. |
| G4 | **Device floor for local LLM.** 4-bit 1–1.5B models need ~2 GB free RAM. | **iPhone 12 and later** get the local LLM; older devices keep V1's retrieval-only Tier B. Detect by RAM, not model name. | Honest performance beats a crashing demo. |

Everything below assumes the recommendations; if you decide differently, only Track B reshuffles.

---

## 2. Policy amendments (write into CLAUDE.md at Phase 11)

1. **Packages:** allowed only if listed in `PACKAGES.md` with version pin + one-line justification.
   Candidates: `mlx-swift` / `llama.cpp` (LLM), `WhisperKit` (ASR, optional), `FluidAudio`
   (diarization, optional). Nothing else without a new decision.
2. **Network:** `NetworkAuditTests` stays, and stays strict. The allowlist gains exactly one file
   (`Core/Models/ModelDownloader.swift`). A new test asserts the downloader can only *GET* from
   the pinned model host and that no other file touches networking.
3. **Schema:** V1 froze `SchemaV1`. V2 is the one sanctioned migration: `SchemaV2` +
   `SchemaMigrationPlan` (lightweight, additive). All V2 fields land in one migration —
   never dribble schema changes across phases.
   New in V2: `Conversation` model (id, title, createdAt, updatedAt);
   `Session.audioFileName: String?` (G3); `ChatMessage` unchanged (already has `conversationId`).

---

## 3. Track A — Conversational RAG 2.0 (the chatbot, done right)

V1's hybrid chat answers single questions. V2 makes it a conversation.

**A1. Multi-turn memory.** Keep one fresh model session per call (V1 rule stands — statelessness
is what makes backends swappable). Conversation context is *assembled into the prompt*, budgeted:
- Rolling conversation summary (~150 tokens, regenerated every ~6 turns) + last 4 turns verbatim.
- `TokenBudgeter` becomes backend-aware: budget = `gateway.contextSize` (4,096 for Apple FM,
  8k–32k for the local LLM) minus reserves. The §3 arithmetic generalizes; never hardcode.

**A2. Conversation-aware retrieval.** Follow-ups like "and who owns it?" retrieve garbage as-is.
Before retrieval, a cheap gateway call rewrites the message into a standalone query
("who owns the billing migration?") using the rolling summary. Skip the rewrite for the first turn.

**A3. Hybrid retrieval (semantic + keyword).** Add BM25 over chunk text (pure Swift, ~150 lines,
in-memory index rebuilt with the vector index) and fuse with vector results via Reciprocal Rank
Fusion. Fixes the classic embedding failure: exact names, invoice numbers, acronyms.

**A4. Streaming answers.** `ModelGateway` gains
`streamRespond(...) -> AsyncThrowingStream<String>` (FoundationModels `streamResponse` /
local-LLM token callback). The chat renders tokens as they arrive.

**A5. Threads & product surface.** Multiple conversations (auto-titled from the first exchange),
scope filter (Everything / this document / this session), suggested follow-up chips after each
answer (generated in the same guided-gen call as the answer — zero extra latency), and V1's
source citations kept everywhere.

**A6. Rerank stage (quality-gated, Phase 16).** Retrieve top-20 → tiny Core ML cross-encoder
reranks → keep top-6 → budget-pack. Only ships if the eval harness shows it beats RRF alone.

---

## 4. Track B — Portable model layer (not hostage to Apple Intelligence)

Every model slot in V1 is already a protocol. V2 adds implementations and a router.

**B1. MiniLM embeddings (Phase 11 — the unblocker).**
`all-MiniLM-L6-v2` → Core ML (384-dim, INT8, ~25 MB, bundled). Hand-rolled WordPiece tokenizer
(~200 lines Swift + bundled `vocab.txt` — no package needed). Slots behind `EmbeddingService`;
the existing `embeddingDimension` mismatch machinery already forces the index rebuild.
Wins: **grounded Ask works in the simulator** (E5 doesn't), measurable quality via the eval
harness, and one embedder across all devices.

**B2. Local LLM (Phase 14).** One-day spike first: run Qwen2.5-1.5B-Instruct-4bit and
Llama-3.2-1B-4bit on the test iPhone under both **MLX-Swift** and **llama.cpp**; pick on
tokens/sec, memory, thermals, API ergonomics (leading hypothesis: MLX for Swift-native +
Metal performance; llama.cpp if GGUF ecosystem breadth matters more).
`LocalLLMGateway: ModelGateway` — call sites don't change *at all*; guided generation maps to
JSON-schema-constrained sampling with a validate-and-retry wrapper.

**B3. Model Manager + downloader (Phase 15).** Settings-level screen: available models, size,
downloaded state, disk usage, delete, a "benchmark" button (tokens/sec on-device), and
per-feature routing. Downloader: consent screen (what, from where, how big, "nothing is ever
uploaded"), pinned host, resumable `GET`, SHA-256 verify, background-safe. This is allowlist
entry #1 (see §2).

**B4. The router.** `FeatureRouter` picks a backend per call:
`Summaries/Ask → Apple FM if tierA, else LocalLLM if installed+RAM-ok, else retrieval-only`.
User-overridable in Model Manager ("Always use local model"). **Product headline: an iPhone 12
owner gets summaries and the chatbot** — V1 gave them passages only.

**B5. Whisper ASR (optional, Phase 19).** WhisperKit + `whisper-base` as a *selectable*
`TranscriptionService`: transcription in the simulator, better accuracy/language coverage;
SpeechAnalyzer stays the battery-friendly default.

---

## 5. Track C — Signature features (the wow, ranked by wow-per-effort)

| # | Feature | What it is | Phase |
|---|---|---|---|
| C1 | **Live Insights** | While recording, every ~90s of finalized segments passes through a small guided-gen call; action items/decisions surface as cards *during* the meeting. "It caught the action item before the meeting ended." | 19 |
| C2 | **Dynamic Island recording** | Live Activity: timer + waveform in the Dynamic Island / lock screen while recording. Consent-visible and gorgeous. | 18 |
| C3 | **Tap-to-play transcript** | (G3) Retained audio synced to segments — tap a line, hear that moment. Waveform scrubber in session detail. | 17 |
| C4 | **Siri + Shortcuts + widgets + Spotlight** | App Intents: "Start an EchoMind session", "Ask EchoMind …". Home-screen widget (recent sessions / open action items). Sessions in Spotlight (CoreSpotlight, on-device). | 18 |
| C5 | **Voice ask + spoken answers** | Dictate the question (reuse ASR stack), answer read by `AVSpeechSynthesizer`. Hands-free mode = car/kitchen use case. | 19 |
| C6 | **Speaker labels** | Diarization via FluidAudio (Core ML, on-device) — "who said what", per-speaker talk-time chart. `speakerLabel` field has been waiting since Phase 1. Spike first; ship only if quality holds. | 20 |
| C7 | **Knowledge graph** | Entities (people/projects/decisions) extracted per session (NL framework NER + guided gen), rendered as an interactive force-directed Canvas graph — *see* your knowledge connect across meetings. Demo gold. | 21 |
| C8 | **Weekly digest + Reminders hand-off** | Monday local notification with a generated week-in-review; one-tap export of action items to Apple Reminders (EventKit, local). | 21 |
| C9 | **On-device translation** | Translate transcripts via the Translation framework (on-device, fits the privacy story). | 21 |

Cut candidates if time presses: C9, C7 (in that order). C1–C4 are the sales demo.

---

## 6. Track D — UI overhaul (from functional to covetable)

**D0. Design system first (Phase 13, before any screen).** `Core/Design/`: color tokens
(light/dark, semantic), type scale, spacing/radius scale, component library (cards, chips,
buttons, badges, source pills). Every later screen consumes tokens — no ad-hoc styling. A
designed app icon (replacing the placeholder) with dark/tinted variants.

**D1. iOS 26 Liquid Glass adoption.** `glassEffect` / `GlassEffectContainer` on toolbars, tab
bar, floating controls, chat input — the app reads as native next-gen, not a template.

**D2. The recording screen is the hero.**
- Real-time waveform: `TimelineView` + `Canvas` fed by the existing level stream; Metal shader
  (`layerEffect`) ambient glow behind it.
- Breathing record button (`PhaseAnimator` + `symbolEffect`), animated `MeshGradient` backdrop
  that reacts to audio level, volatile-text shimmer via custom `TextRenderer`.
- Haptics on start/stop/finalized-segment (`sensoryFeedback`).

**D3. Chat that feels alive.** Streaming typewriter rendering, glass bubbles, animated typing
indicator, follow-up chips that spring in, source cards with page-thumbnail styling, scroll
effects (`scrollTransition`).

**D4. Motion with purpose.** Session list → detail via `navigationTransition(.zoom)` +
`matchedGeometryEffect` on the waveform thumbnail; summary sections stagger in; `Charts`-powered
insights header on Home (sessions/week, talk time). Respect `prefers-reduced-motion` throughout.

**D5. Polish pass (Phase 22).** Empty states illustrated, all-size Dynamic Type audit, dark
mode sweep, App Store screenshots/preview video assets.

---

## 7. Execution flow — milestones and phases

Dependencies: `11 → 12 → 13` · `14 → 15` (needs 11's eval harness) · `17 → 20` (diarization
wants retained audio) · 18/19 independent after 13 · 21 after 12 · 22 last.

### V2.0 — "Grounded everywhere" (Phases 11–13, ~2 weeks)
**P11 · MiniLM embeddings + eval harness**
Build: conversion script (`tools/convert_minilm.py`, coremltools — run on this Mac); WordPiece
tokenizer + tests; `CoreMLEmbeddingService`; retrieval eval harness (the §6.6 10-query eval as
a repeatable debug screen + XCTest). Policy edits: CLAUDE.md amendments, `PACKAGES.md`.
Gate: grounded Ask **passes in the simulator**; eval ≥ 7/10; rebuild-on-dimension-change proven.
**P12 · Conversational core**
Build: `SchemaV2` + migration; threads; rolling summary; query rewrite; BM25 + RRF; streaming
gateway + UI; follow-up chips; scope filter. Mock-gateway tests for memory budgets, rewrite,
fusion ranking, stream assembly.
Gate: 10-turn conversation with follow-ups stays coherent; V1 single-shot tests still green.
**P13 · Design system + hero screens**
Build: `Core/Design` tokens/components; Liquid Glass shell; recording hero (waveform, mesh,
haptics); chat restyle; zoom transitions; new app icon.
Gate: every screen consumes tokens; reduced-motion + AX5 Dynamic Type audits pass.
→ **Ship V2.0 to TestFlight.**

### V2.1 — "Own the model" (Phases 14–16, ~2 weeks)
**P14 · Local LLM** — engine spike (day 1, decision recorded in plan); `LocalLLMGateway`;
backend-aware `TokenBudgeter`; guided-gen JSON constraint + retry. Gate: summaries + chat run
end-to-end on the local model with Apple Intelligence toggled **off**.
**P15 · Model Manager + downloader** — consent flow, pinned host + SHA-256, disk mgmt,
benchmarks, `FeatureRouter` + routing UI; network-audit test extended (downloader-only
exception). Gate: iPhone 12-class device (or AI-off Tier A) gets full AI; airplane-mode
everything-still-works after download.
**P16 · Retrieval quality pass** — rerank spike behind the eval harness; chunking tune; ship
only what measurably wins. Gate: eval ≥ 8/10 or documented no-ship.
→ **Ship V2.1.** *(This is the release with the marketable claim: "full AI on any iOS 26 iPhone.")*

### V2.2 — "Alive while you record" (Phases 17–19, ~2 weeks)
**P17 · Audio retention + tap-to-play** (G3): AAC写 alongside capture; segment-seek playback;
waveform scrubber + thumbnails; storage accounting + wipe coverage.
**P18 · System presence**: Live Activity/Dynamic Island; App Intents/Siri; widgets; Spotlight.
*Human once: add Widget-extension target + App Group in Xcode (pbxproj is off-limits to CC).*
**P19 · Live Insights + voice ask** (+ optional WhisperKit): insight cards during recording;
dictated questions; spoken answers; hands-free mode.
→ **Ship V2.2.**

### V2.3 — "Depth & delight" (Phases 20–22, ~2 weeks)
**P20 · Diarization spike → speaker labels** (only if quality holds on real meetings).
**P21 · Knowledge graph + digest + Reminders export + translation.**
**P22 · Polish + perf/battery audit + App Store assets.** Re-run the full V1 device matrix
+ new rows (local-LLM thermals, download resume, Live Activity, audio playback).
→ **Ship V2.3 / public beta.**

Rough total: **8–10 focused weeks**, each milestone independently shippable.

---

## 8. Testing additions

- **Eval harness is the spine** (P11): retrieval eval codified, run at every retrieval-touching
  gate; scores recorded in commit messages (V1 §6.6 discipline, now automated).
- Unit: tokenizer golden-vectors vs. Python reference; BM25 scoring; RRF ordering; conversation
  budget math per backend contextSize; downloader checksum/resume (local file:// fixtures).
- The simulator can now cover embeddings (MiniLM) — CI-testable RAG end-to-end with a mocked
  gateway; local LLM, audio, Live Activities, diarization remain device-only.
- Extend `TESTLOG.md` matrix rather than fork it.

## 9. Top risks

| Risk | Mitigation |
|---|---|
| Local LLM quality disappoints at 1–1.5B | Spike scores quality day 1; routing keeps Apple FM primary on Tier A; model list is swappable (downloadable) so better small models drop in without an app update |
| Thermals/battery on long local-LLM sessions | Benchmarks in Model Manager; router can degrade to retrieval-only under thermal pressure (`ProcessInfo.thermalState`) |
| Model download = privacy-story erosion | Consent screen copy, download-only audit test, App Privacy unchanged, docs in-app ("nothing ever leaves") |
| Diarization accuracy embarrasses | It's a spike with a kill criterion, not a commitment |
| Scope creep across 12 phases | Milestones are shippable cuts; C9→C7 are the pre-agreed drop order |
| SchemaV2 migration bug corrupts user data | One migration, migration tests on fixture stores, TestFlight soak before wide rollout |

## 10. Human prerequisites (you)

1. Sign off on **G1–G4** (§1).
2. A Tier A iPhone for baseline testing **and** ideally an iPhone 12/13-class device — the
   whole point of V2.1 is proving full AI there.
3. Somewhere to host model files for the downloader (any static host/CDN/GitHub Releases;
   needed by P15).
4. Xcode GUI moments: Widget extension target + App Groups (P18), Push/BackgroundTasks
   capability for the digest (P21), plus the V1 leftovers (deployment target → 26.0,
   launch-screen key).
5. Optional but wise: a designed app icon from a designer for P13 (I'll ship a programmatic
   one regardless).

---

## 11. Build progress log

- **V2.0 (P11–13): SHIPPED to branch `v2`.** NLEmbedding-grounded RAG in the
  simulator, conversational core (BM25+RRF, memory, follow-ups), design system +
  UI overhaul. 146→ tests green.
- **V2.1 (P14–15): CODE-COMPLETE, pending package + device.**
  - P14: `LocalLLMEngine` seam, `GuidedJSON` (reuses `@Generable` schema via
    `GeneratedContent(json:)`), `LocalLLMGateway`, `FeatureRouter`, `LocalModelCatalog`.
    `MLXEngine` behind `#if canImport(MLXLLM)`.
  - P15: `RoutingModelGateway` (wired as the app gateway), `AISettingsStore`,
    `ModelDownloadService` + `MLXModelDownloader` (`#if canImport`), `ModelStorage`
    marker truth, `AIModelsView` manager with consent. 159 tests green.
  - **Blocked on human:** add `ml-explore/mlx-swift-examples` (MLXLLM, MLXLMCommon)
    in Xcode, then device-download a model and verify local inference with Apple
    Intelligence off. Reconcile `MLXEngine.swift` if the MLX API drifted. Extend the
    network-audit test with the downloader-only allowlist once the package is present.
- **P16 (retrieval quality): SHIPPED.** MMR diversity reranking (`MMRReranker`, λ=0.7)
  wired into `RAGPipeline` hybrid retrieval (fused pool→MMR→top-6; BM25-only exact hits
  preserved). Measured: diversity win proven deterministically (MMRRerankerTests);
  handbook recall not regressed on real NLEmbedding vectors (RetrievalEval gate). 165 tests green.
