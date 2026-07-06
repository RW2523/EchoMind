# EchoMind iOS — Final Execution Plan (Claude Code Edition)

**V1 scope:** private live transcription → saved sessions → on-device AI summaries → local RAG Q&A. No network calls, no backend, no third-party dependencies.

**How to use this file:** save it as `PLAN.md` at the root of your repo. Claude Code will read it. Each phase below has a paste-ready prompt.

---

## 0. What changed from the draft plan

1. **4,096-token reality.** The on-device Foundation Model has a fixed 4,096-token context window (input + output combined; overflow throws an error). The single-shot summary and RAG prompts from the draft would fail on any real meeting. Replaced with a token-budgeted, map-reduce design (§3).
2. **iOS 26 deployment floor.** Standardizes the speech stack on SpeechAnalyzer (built for long-form audio) and eliminates the legacy SFSpeechRecognizer path. The three device modes collapse to two tiers (§2).
3. **No cloud, no backend in V1.** Cloud arrives in V1.1 via iOS 27's LanguageModel protocol / Private Cloud Compute (32K context, free under the App Store Small Business Program). The model gateway is a thin protocol designed so that swap is trivial (§10). This deletes the FastAPI backend and the API-key problem from V1 entirely.
4. **Background audio promoted to a core requirement.** Users lock their phone during meetings; recording must survive it. Now Phase 2, with interruption handling.
5. **Embeddings are a real work item, not a bullet.** V1 uses `NLContextualEmbedding` (built into iOS) behind an `EmbeddingService` protocol; a converted MiniLM Core ML model is the V1.1 upgrade if retrieval quality disappoints.
6. **Recording consent added.** Onboarding consent notice + in-app recording indicator (two-party-consent states, GDPR, App Review).

---

## 1. Locked technical decisions

| Area | Decision |
|---|---|
| Language / UI | Swift 6, SwiftUI, Swift Concurrency (async/await, actors) |
| Minimum OS | iOS 26.0 (iPhone 11 / SE 2nd gen and later) |
| Audio | AVAudioEngine + AVAudioSession, Background Modes → Audio |
| Speech | SpeechAnalyzer + SpeechTranscriber, on-device, locale assets via AssetInventory |
| Generation | Apple Foundation Models (on-device only in V1), `@Generable` guided generation |
| Token management | TokenBudgeter using `contextSize` / `tokenCount(for:)` (iOS 26.4+), char-estimate fallback |
| Embeddings | NLContextualEmbedding, mean-pooled + L2-normalized, behind `EmbeddingService` protocol |
| Vector search | Brute-force cosine via Accelerate/vDSP (pre-normalized vectors → dot product) |
| Storage | SwiftData; embeddings as packed `[Float]` in `Data`; file protection `.completeUnlessOpen` |
| Backend / cloud | None in V1. V1.1: PCC / third-party via iOS 27 LanguageModel protocol |
| Dependencies | Zero third-party packages in V1 |
| Project format | Xcode synchronized folder groups (Claude Code adds files without touching the pbxproj) |
| Assistant | Claude Code, one phase per session, plan mode first |

---

## 2. Device tiers (replaces the 3-mode matrix)

**Tier A — Apple Intelligence devices** (iPhone 15 Pro / 16 and later, Apple Intelligence enabled): everything, including summaries and generated RAG answers.

**Tier B — all other iOS 26 iPhones:** live transcription, sessions, document import, and **retrieval-only answers** ("here are the relevant passages"). AI buttons render a "requires Apple Intelligence" state.

Tier is determined at runtime from `SystemLanguageModel.default.availability` — handle `.available` and every `.unavailable` reason distinctly (device not eligible / Apple Intelligence not enabled / model not ready), because a Tier A phone with Apple Intelligence toggled off behaves like Tier B and should tell the user why.

---

## 3. Token budget rules (non-negotiable math)

- Window: **4,096 tokens per LanguageModelSession, input + output combined.** Overflow throws `exceededContextWindowSize`; there is no automatic truncation. Rule of thumb: 3–4 characters/token.
- Never hardcode 4096. Use `SystemLanguageModel.contextSize` and `tokenCount(for:)` where available; fall back to `ceil(chars / 3.5)`.
- **Summarization (map-reduce):** split the transcript on segment boundaries into windows of ≤ 2,200 input tokens → each window yields a partial summary capped at ~300 tokens → reduce step combines partials (+ instructions) at ≤ 2,500 input tokens into the final structured summary (~700-token output budget). If a transcript fits in one window, skip the map step.
- **RAG answers:** instructions ≤ 250 + question ≤ 250 + retrieved context ≤ 2,300 (typically 3 chunks of ~200 words) + ~1,000 reserved for the answer.
- Every model call goes through the TokenBudgeter. On an exceeded-context error: drop the lowest-ranked chunk (RAG) or re-split the window (summary) and retry once; if it still fails, fall back to retrieval-only output. One fresh session per call — never accumulate conversation history into a session.

---

## 4. Human prerequisites (things Claude Code cannot do)

1. Apple Developer Program membership; Mac with Xcode 26.x.
2. Test devices: ideally one Tier A iPhone (15 Pro+ with Apple Intelligence on) and one Tier B iPhone.
3. Create the project in Xcode: iOS App → SwiftUI → product name `EchoMind` → minimum deployment iOS 26.0. Keep Xcode's default **synchronized folder groups** — this is what lets Claude Code add Swift files freely without editing the project file.
4. Signing & Capabilities: set your team; add **Background Modes → Audio**.
5. Info tab: add `NSMicrophoneUsageDescription` and `NSSpeechRecognitionUsageDescription` with honest, user-facing strings.
6. Build and run the empty app on a real device once (proves signing works).
7. Install Claude Code (`npm install -g @anthropic-ai/claude-code`, Node 18+), run `claude` in the repo, authenticate.
8. `git init`, commit the empty project, then add `CLAUDE.md` and `PLAN.md` (this file) at the repo root.

---

## 5. CLAUDE.md (paste verbatim at repo root)

```markdown
# EchoMind — private meeting memory for iPhone

Live transcription → saved sessions → on-device AI summaries → local RAG Q&A.
Privacy-first: NO network calls anywhere in V1. Min iOS 26.0, Swift 6, SwiftUI,
SwiftData, zero third-party dependencies. Full spec and phase plan: PLAN.md.

## Build & test
- Build: xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
- Test:  xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
- Always build after changes. Fix every error and warning you introduced.
- (Substitute any installed simulator name if iPhone 17 Pro is unavailable.)

## Architecture (MVVM + protocol-based services)
- Features/<Feature>/{View,ViewModel}
- Core/Audio          AVAudioEngine capture, session config, interruptions
- Core/Transcription  SpeechAnalyzer behind TranscriptionService protocol
- Core/AI             ModelGateway protocol, FoundationModelService,
                      TokenBudgeter, Summarizer
- Core/RAG            TextChunker, EmbeddingService protocol, VectorSearch,
                      RAGPipeline
- Core/Storage        SwiftData models + repository protocols
- Models/             pure data types

## Hard rules
- Every service = protocol + one implementation; view models depend on protocols.
- All Foundation Models calls go through TokenBudgeter. Never assume more than
  a 4,096-token context. Always handle exceededContextWindowSize. Budgets: PLAN.md §3.
- One fresh LanguageModelSession per call; never accumulate history in a session.
- No force unwraps. No singletons except AppDependencies (composition root).
- No new packages or network calls without asking me first.
- Never edit the .xcodeproj: new Swift files inside existing folders are picked
  up automatically (synchronized groups).
- Audio/speech/embedding work runs off the main thread; UI updates on @MainActor.
- Keep files under ~300 lines; split when larger.
```

Optional but recommended — a reusable build command at `.claude/skills/build-check/SKILL.md`:

```markdown
---
name: build-check
description: Build EchoMind for the simulator and fix any compile errors from recent changes
---
Run: xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -60
If it fails, read the errors, fix them, and rebuild until clean.
Never delete failing code or silence warnings just to make the build pass.
```

---

## 6. Working rules for every phase

1. One phase per Claude Code session. Start in **plan mode** (Shift+Tab, or `claude --permission-mode plan`), paste the phase prompt, review the plan, approve.
2. Let it implement, then review the diff file by file. You are the reviewer; don't rubber-stamp.
3. Run `/build-check`, then **verify on a real iPhone** — audio, speech, and Foundation Models behavior cannot be judged from the simulator alone.
4. Commit at every green milestone (`feat(phase-3): live transcription`), then `/clear` before the next phase.
5. If Claude Code fails the same fix twice: `git checkout .`, shrink the ask into smaller steps, retry.

---

## 7. Phase-by-phase execution

### Phase 1 — App skeleton, storage, onboarding + consent

**You do first:** nothing beyond §4.

**Paste into Claude Code:**

```text
Read CLAUDE.md and PLAN.md §3 and §8, then build the EchoMind skeleton.

1. SwiftData models in Core/Storage per PLAN.md §8: Session, TranscriptSegment,
   Document, KnowledgeChunk, ChatMessage, AppSettings.
   - KnowledgeChunk.embedding is Data (packed [Float]).
   - Configure the ModelContainer store with file protection .completeUnlessOpen
     so background recording can keep writing while the phone is locked.
2. Repository protocols + SwiftData implementations: SessionRepository,
   DocumentRepository, ChunkRepository.
3. AppDependencies composition root, injected through the SwiftUI environment.
4. Tab navigation: Home, Sessions, Knowledge, Ask, Settings — real navigation,
   placeholder content.
5. First-launch onboarding: Welcome → Privacy explainer ("everything stays on
   this iPhone") → Recording-consent notice (user acknowledges they are
   responsible for informing participants before recording; keep the copy
   plain, not legalese) → permission priming screens that EXPLAIN mic and
   speech permissions but defer the actual system prompts to first recording.
6. PermissionManager service wrapping AVAudioApplication record permission and
   SFSpeechRecognizer authorization status.

Acceptance: builds clean; onboarding shows exactly once (persisted flag);
tabs navigate; a debug-only button inserts and fetches a dummy Session.
```

**Verify:** fresh install shows onboarding once; relaunch skips it. **Commit.**

---

### Phase 2 — Audio engine + background recording

**You do first:** confirm Background Modes → Audio is enabled in Signing & Capabilities.

**Paste into Claude Code:**

```text
Implement Core/Audio for EchoMind. Read CLAUDE.md first.

1. AudioEngineManager (actor): owns AVAudioEngine + AVAudioSession lifecycle.
   Configure the session for speech recording, activate on start, deactivate
   on stop. Expose start() -> AsyncThrowingStream<AVAudioPCMBuffer> from an
   input-node tap, plus stop(), and a published elapsed-time/level state for UI.
2. Interruption handling via AVAudioSession notifications:
   - interruption began (phone call, Siri): pause capture, mark state.
   - interruption ended with shouldResume: resume automatically.
   - route change (AirPods connect/disconnect): keep capturing on the new input
     without crashing or losing the session.
   - media services reset: tear down and rebuild the engine.
3. Background continuation: recording must keep running when the screen locks
   or the app is backgrounded (Background Modes audio is already enabled).
   No always-listening; only while a user-started session is active.
4. In-app recording indicator component: red dot + elapsed timer, shown on the
   live screen whenever capture is active.
5. Unit-test what's testable (state transitions on synthetic notifications).

Acceptance: start/stop works repeatedly; buffers flow; a phone call pauses and
resumes cleanly; locking the screen for 2+ minutes does not stop capture.
```

**Verify on device:** lock the phone mid-capture; call yourself mid-capture. **Commit.**

---

### Phase 3 — Live transcription

**Paste into Claude Code:**

```text
Implement Core/Transcription using the iOS 26 SpeechAnalyzer stack. Read
CLAUDE.md first.

1. TranscriptionService protocol:
   start(locale:) -> AsyncThrowingStream<TranscriptionUpdate>; stop().
   TranscriptionUpdate carries text, isFinal, and audio time range.
2. SpeechAnalyzerTranscriber implementation: SpeechAnalyzer + SpeechTranscriber,
   on-device. Check locale support; download/install the locale model via
   AssetInventory with visible progress before first use. Consume the
   AVAudioPCMBuffer stream from AudioEngineManager (convert format if needed).
   Emit volatile (partial) results and finalized results with time ranges.
3. LiveTranscriptView: Start/Stop, recording indicator from Phase 2, elapsed
   timer, finalized text in primary color with the current volatile text
   appended in secondary color, auto-scroll.
4. Persistence: create the Session when recording starts and persist each
   FINALIZED segment incrementally as it arrives — not only on Stop — so a
   crash or force-quit loses at most the volatile tail. On Stop, finalize
   duration and default title "Meeting <date, time>".
5. Error states with user-readable messages: mic denied, speech denied, locale
   unsupported, asset download failed, transcriber failure mid-session.

Acceptance: speak for 2+ minutes; partials appear in under ~1s; segments are
in the store before Stop is tapped; screen-locked recording keeps transcribing
and the UI catches up on unlock; force-quitting mid-session preserves all
finalized segments.
```

**Verify on device:** long dictation, lock test, force-quit test. **Commit.**

---

### Phase 4 — Sessions

**Paste into Claude Code:**

```text
Build the Sessions feature. Read CLAUDE.md first.

1. SessionsView: list sorted by date — title, date, duration, 2-line transcript
   preview; searchable by title and transcript text.
2. SessionDetailView: full transcript rendered from segments with timestamps,
   summary section placeholder (Phase 5), rename (inline), delete with
   confirmation (cascades segments and any knowledge chunks), and export via
   ShareLink as Markdown and plain text (title, date, duration, timestamped
   transcript).
3. Home screen becomes real: Start Live Transcript, Ask My Knowledge, Import
   Document, and the 3 most recent sessions.

Acceptance: sessions from Phase 3 appear immediately after recording; rename,
delete, search, and export all work; deleting a session leaves no orphaned
segments or chunks.
```

**Verify, commit.**

---

### Phase 5 — AI foundation: gateway, token budgeter, summaries (Tier A)

**Paste into Claude Code:**

```text
Implement Core/AI. Read CLAUDE.md and PLAN.md §3 (token budgets) first — the
budgets there are hard requirements.

1. ModelGateway protocol with two methods:
   respond(instructions:prompt:maxOutputTokens:) async throws -> String
   generate<T: Generable>(instructions:prompt:as:) async throws -> T
   Design it so a future implementation backed by iOS 27's LanguageModel
   protocol (Private Cloud Compute or a third-party provider) can slot in with
   no call-site changes.
2. FoundationModelService: ModelGateway implementation over
   SystemLanguageModel / LanguageModelSession. One fresh session per call.
   Expose an AvailabilityStatus (tierA / tierB(reason)) derived from
   SystemLanguageModel availability, distinguishing device-not-eligible,
   Apple-Intelligence-not-enabled, and model-not-ready. Publish it for
   Settings and for feature gating.
3. TokenBudgeter: prefers contextSize and tokenCount(for:) when the OS
   provides them (iOS 26.4+), otherwise estimates ceil(chars / 3.5). Provides
   fit(instructions:prompt:reservedOutput:) checks and a pack(items:budget:)
   helper that adds ranked items until the budget is hit.
4. @Generable MeetingSummary: overview (String), keyDecisions [String],
   actionItems [ActionItem{text, owner?}], risks [String],
   openQuestions [String].
5. Summarizer (map-reduce per PLAN.md §3):
   - Split the transcript on segment boundaries into windows ≤ 2,200 input
     tokens; single-window transcripts skip straight to reduce.
   - Map: each window -> plain-text partial summary (~300-token cap).
   - Reduce: partials -> MeetingSummary via guided generation, ≤ 2,500 input.
   - Catch exceededContextWindowSize: re-split the offending window once and
     retry; if it still fails, surface a clear error, never a crash.
6. Wire "Generate Summary" into SessionDetailView (Tier A): progress state,
   store the result on the Session, render the structured sections. Tier B
   shows a "Requires Apple Intelligence" explanation instead of the button.
7. Seed a debug fixture: a ~9,000-word fake transcript for testing.

Acceptance: the 9,000-word fixture summarizes with zero context-window errors;
sections render; regenerating replaces the stored summary; Tier B state
displays correctly when Apple Intelligence is off.
```

**Verify on a Tier A device** (and with Apple Intelligence toggled off). **Commit.**

---

### Phase 6 — Document import

**Paste into Claude Code:**

```text
Build document import. Read CLAUDE.md first.

1. Knowledge tab: list of knowledge sources — imported documents AND saved
   session transcripts — with type icon, title, date, size; swipe to delete
   (cascades chunks).
2. Import flow via fileImporter for .txt, .md, .pdf:
   - PDF text extraction with PDFKit, preserving page numbers per block.
   - If a PDF has no text layer (scanned), reject it with a friendly
     "scanned PDFs aren't supported yet" message. No OCR in V1.
   - Clean extracted text: normalize whitespace, repair hyphenated line
     breaks, strip null/control characters.
   - Save a Document row with title (filename), type, and full text; status
     field starts as .imported (indexing happens in Phase 7).
3. Enforce a sane size cap (e.g. 5 MB of extracted text) with a clear error.

Acceptance: importing a multi-page PDF shows it in Knowledge with correct
title and page count; a .md file imports; a scanned PDF is rejected politely;
delete removes the document.
```

**Verify, commit.**

---

### Phase 7 — Chunking, embeddings, vector search

**Paste into Claude Code:**

```text
Implement the retrieval half of Core/RAG. Read CLAUDE.md first. This phase has
real algorithmic content — write unit tests as you go.

1. TextChunker: ~200-word chunks with ~40-word overlap, breaking on sentence
   boundaries (never mid-sentence). Carries sourceId, sourceType
   (document/session), chunkIndex, pageNumber? (documents), timestamp?
   (transcript segments).
2. EmbeddingService protocol: embed(_ texts: [String]) async throws -> [[Float]].
   NLContextualEmbeddingService implementation: ensure/download the language
   asset on first use, produce token embeddings, mean-pool into one vector,
   L2-normalize. Batch inputs. All off the main actor.
3. Vector packing utilities: [Float] <-> Data round-trip (little-endian),
   with a unit test.
4. Indexer service: on document import and on session save, chunk + embed +
   store KnowledgeChunks in a background task with progress reported to the
   Knowledge tab (status: .indexing -> .ready). Add "Rebuild index" to
   Settings (wipes and re-indexes everything).
5. VectorSearch: load candidate vectors, compute cosine via vDSP dot product
   (vectors are pre-normalized, so dot == cosine), return top-K with scores.
   Brute force is the design — no index structures.
6. Unit tests: chunk boundaries and overlap; cosine correctness against a
   hand-computed example; top-K ordering; Data round-trip.

Acceptance: importing a 30-page PDF indexes to .ready; a query like "refund
policy" returns visibly relevant top-5 chunks; search over a few thousand
chunks completes in well under 100ms on device.
```

**Verify on device with a real PDF. Commit.**

---

### Phase 8 — Ask (RAG question answering)

**Paste into Claude Code:**

```text
Build the Ask feature end to end. Read CLAUDE.md and PLAN.md §3 first.

1. AskView: chat-style UI over ChatMessage storage; input bar; answer cards.
2. RAGPipeline:
   - Embed the question (EmbeddingService).
   - Retrieve top-6 chunks (VectorSearch).
   - TokenBudgeter packs instructions (≤250 tokens) + question + best chunks
     into ≤2,800 input tokens (typically 3 chunks survive), reserving ~1,000
     for output.
   - Tier A: ModelGateway.respond with instructions: answer ONLY from the
     provided context; if the context doesn't contain the answer, reply
     exactly "I couldn't find this in your saved knowledge."
   - On exceededContextWindowSize: drop the lowest-ranked chunk, retry once,
     then fall back to retrieval-only.
3. Answer card: the answer, then source snippets — chunk text preview +
   source title + page/timestamp — tapping a source opens the document or
   session at that location.
4. Tier B and any generation-failure path: retrieval-only card — "Here's what
   I found in your knowledge" with the top passages. This is a first-class
   experience, not an error screen.
5. Persist ChatMessages with their source references.

Acceptance: asking about content from a seeded meeting returns a grounded
answer citing the right session; asking something absent returns the exact
not-found sentence; with Apple Intelligence off, the same question returns
useful passages instead.
```

**Verify both tiers on device. Commit.**

---

### Phase 9 — Privacy, settings, data controls

**Paste into Claude Code:**

```text
Finish Settings and the privacy posture. Read CLAUDE.md first.

1. Settings screen:
   - Model status: Tier A/B with the specific reason and, where applicable,
     a hint ("Enable Apple Intelligence in iOS Settings").
   - Storage usage: sessions / documents / index sizes, computed for real.
   - Recording-consent reminder text (same copy as onboarding).
   - Rebuild index (from Phase 7).
   - Export all data: per-session Markdown files + imported-documents list,
     handed to the share sheet as multiple items.
   - Delete all data: type-to-confirm, wipes every store and the index.
2. Zero-network audit: search the codebase for URLSession/Network usage; add
   a unit test that scans source files and fails if networking APIs appear
   outside an explicit allowlist file (which starts empty). This is our
   regression guard for the V1 privacy promise.
3. Sweep all user-facing error copy for tone and accuracy.

Acceptance: settings values are real, not placeholders; delete-all leaves a
truly empty app; the network-audit test passes and demonstrably fails if a
URLSession call is introduced.
```

**Verify, commit.**

---

### Phase 10 — Hardening + TestFlight

**You do first:** create the App Store Connect record; fill App Privacy as data-not-collected (true in V1); answer export-compliance (standard OS encryption only).

**Paste into Claude Code:**

```text
Hardening pass before TestFlight. Read CLAUDE.md first.

1. Run the full test suite; fix failures.
2. Audit every async path for cancellation safety when views disappear
   mid-operation (recording, indexing, summarizing, asking).
3. Low-storage behavior: fail writes gracefully with a clear message.
4. Accessibility pass: labels on controls, Dynamic Type on transcript and
   answer views.
5. Empty states for every tab (no sessions, no knowledge, no chats).
6. App icon placeholder + launch screen if missing.
```

**Then run the manual test matrix (§9) yourself, archive in Xcode, upload, and invite internal testers.**

---

## 8. Final data model

```text
Session:            id, title, createdAt, updatedAt, duration, summaryJSON?,
                    sourceType (live/import), tags [String]
                    (full transcript is DERIVED from segments — never stored twice)

TranscriptSegment:  id, sessionId, text, startTime, endTime, speakerLabel?,
                    createdAt

Document:           id, title, fileName, fileType, textContent, pageCount?,
                    status (imported/indexing/ready/failed), createdAt

KnowledgeChunk:     id, sourceId, sourceType (document/session), text,
                    embedding (Data, packed [Float]), chunkIndex, pageNumber?,
                    timestamp?, createdAt

ChatMessage:        id, conversationId, role, content,
                    sourceRefs [{sourceId, sourceType, chunkId}], createdAt

AppSettings:        onboardingComplete, consentAcknowledged,
                    preferredLocale, lastIndexRebuild
```

Notes: no `privateOnlyMode` or `cloudFallbackEnabled` flags in V1 — there is no cloud to toggle. Add them in V1.1 with cloud OFF by default.

---

## 9. Manual test matrix (run before every TestFlight build)

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
| 11 | Delete all data | App equals fresh install |
| 12 | Locale asset not yet downloaded (fresh device) | Progress UI, then transcription works |

---

## 10. V1.1 — iOS 27 adoption (fall 2026)

When iOS 27 ships, the Foundation Models framework adds a public LanguageModel protocol so the same session code can target the on-device model, Apple's Private Cloud Compute server model (32K context, no API keys), or third-party providers like Claude and Gemini.

Plan:
1. Add a `PCCModelGateway` implementation behind the existing `ModelGateway` protocol. The 32K window makes most meeting summaries single-shot — keep the map-reduce path as the offline/on-device route.
2. Eligibility caveat: free PCC requires the App Store Small Business Program, under 2M first-time downloads, and a PCC entitlement — and access ends if you outgrow the program, with no paid tier. So also keep a provider-package slot (Claude/Gemini) as the paid escape hatch.
3. Product rules: cloud strictly opt-in, **default off**, with per-request routing visible in Settings; update App Privacy labels the moment any cloud path ships.
4. Other V1.1 candidates, in order: Core ML MiniLM embeddings (if retrieval quality lags), speaker labels, DOCX import, search across sessions, PDF export.

---

## 11. Timeline expectation

Roughly 10–14 focused build days with Claude Code for one experienced Swift developer; 4–6 calendar weeks to a credible TestFlight including real-device soak testing. The schedule risks are Phases 2–3 (audio edge cases) and Phase 7 (embedding quality) — protect time there, not in the UI phases.
