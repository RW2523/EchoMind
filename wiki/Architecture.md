# Architecture

A developer's map of how EchoMind is built. Principles: **one protocol per service**,
**one routed gateway for all AI**, **one `#if canImport` file per optional package**,
**pure logic is exhaustively unit-tested**.

## Layers

```
App/            EchoMindApp, RootView, MainTabView, AppDependencies (composition root)
Features/       <Feature>/{View, ViewModel} — SwiftUI + @Observable
Core/Audio      AudioEngineManager (capture), AudioStore, AudioFileWriter, interruptions
Core/Transcription  SpeechAnalyzerTranscriber behind TranscriptionService
Core/AI         Gateways, budgeter, summarizer, report/classify/memory/continuity pipelines
Core/RAG        chunking, embeddings, vector search, BM25, RRF, MMR, RAGPipeline, clustering
Core/Voice      VoiceSessionController + STT/TTS/VAD/streaming seams
Core/Security   AppLockAuthenticating (LocalAuthentication) — Face ID app lock
Core/Integrations  ReminderExporting (EventKit) — action items → Apple Reminders
Core/Storage    SwiftData @Model + @ModelActor repositories; SchemaV1
Core/Design     DesignSystem (dark navy theme, components, effects)
Models/         pure Sendable value types (snapshots) that cross actor boundaries
```

## Composition root

`AppDependencies` (`@MainActor @Observable`) builds every service once and is injected via
the SwiftUI environment. View models receive only the protocols they need. There are no
singletons except this composition root.

## The AI gateway (the spine)

All model calls go through `ModelGateway`:

```
respond(instructions:prompt:maxOutputTokens:) -> String
generate(instructions:prompt:as: T.Type) -> T   // T: @Generable (guided JSON)
```

`RoutingModelGateway` picks a backend **per call** via `FeatureRouter`:

```
Apple Intelligence available?      → FoundationModelService (Apple FM)
  else local model downloaded?     → LocalLLMGateway (MLX)     [1.1, #if canImport]
    else                            → retrieval-only (throws modelUnavailable)
```

- Non-Apple backends emulate guided generation with `GuidedJSON` — the model emits JSON
  matching Apple's own `GenerationSchema`, parsed back through `GeneratedContent(json:)`
  into the same `@Generable` type. No parallel DTOs.
- Streaming is an optional capability (`StreamingModelGateway`) used by the voice agent;
  non-streaming backends fall back to one chunk.
- Every call passes through `TokenBudgeter` (4,096-token floor; `exceededContextWindow`
  always handled). One fresh session per call — history is never accumulated in a session.

## Storage

SwiftData `@Model` classes never leave `Core/Storage`. Repositories are `@ModelActor`
actors that exchange **Sendable snapshot structs** (`Models/`), so nothing crosses actor
boundaries unsafely under Swift 6 strict concurrency. Schema changes are additive
(`SchemaV1` + defaults → lightweight migration). File protection (`.completeUnlessOpen`)
is set at runtime on the database and audio directory so background-locked recording keeps
working while data stays encrypted at rest.

## RAG pipeline

`ask(question, history:)` and `askStreaming(...)`:

1. Rewrite the question into a standalone query (using recent chat history).
2. **Hybrid retrieve**: vector top-20 (vDSP cosine over stored embeddings) ∪ BM25 top-20 →
   **Reciprocal Rank Fusion** → **MMR** diversity rerank → top-6.
3. Pack chunks under a token budget; prepend a bounded **memory-facts preamble** (dropped
   before chunks — grounding always wins) and a conversation-memory block.
4. One guided call → grounded answer + sources + follow-ups (or conversational reply).

Embeddings default to first-party `NLEmbedding.sentenceEmbedding` (works in the simulator
and on device); `EmbedderResolver` upgrades to a downloaded EmbeddingGemma when linked.

## Meeting intelligence

Triggered after each recording stops, in `ReportPipeline`:

1. **Summarize** (map-reduce) → `MeetingSummary` (overview, decisions, action items, risks,
   questions); persisted; report state `pending → ready`.
   Then **auto-title** (F3): `MeetingTitler` names the session from the overview —
   applied via an atomic `renameIfPlaceholder`, so a user rename always wins.
2. **Continuity** — `MeetingContinuityService` finds the most similar *earlier* sessions by
   session-vector cosine and asks how this meeting continues them.
3. **Grouping** — `SessionClusterer` (pure, order-invariant, embedding-based) clusters
   sessions; `MeetingClassifier` names each cluster canonically (reusing an existing name so
   similar meetings don't fragment). Category lands in `tags[0]`.
4. **Memory** — `MemoryDistiller` adds durable facts / retires stale ones, capped, into the
   `MemoryStore`. Facts are injected into every RAG/voice answer.

## Voice agent

`VoiceSessionController` is a pure state machine (`idle → listening → thinking → speaking`),
cancellable from any state, decoupled from RAG via a callback:

- STT: `VoiceInput` (`LiveVoiceInput` wraps the transcription stack).
- TTS: `SpeechSynthesizing` (`SystemSpeechSynthesizer` floor; Kokoro via `#if canImport`).
- Streaming: `SentenceChunker` turns the token stream into sentences so speech starts on
  sentence one.
- Hands-free: `TurnEndpointer` (transcript-quiescence VAD) + echo cancellation +
  barge-in (stop TTS + generation, reopen a turn).

## Optional packages — the seam

Each third-party engine lives behind exactly one `#if canImport` file, with a first-party
floor, so the app compiles and ships with **zero** packages:

| File | Package | Floor |
|---|---|---|
| `Core/AI/Local/MLXEngine.swift` | MLXLLM | Apple FM |
| `Core/RAG/GemmaEmbeddingService.swift` | MLXEmbedders | NLEmbedding |
| `Core/Diarization/FluidAudioDiarizer.swift` | FluidAudio | (feature hidden) |
| `Core/Voice/KokoroSynthesizer.swift` | FluidAudioTTS | AVSpeechSynthesizer |
| `Core/RAG/SQLiteVecVectorStore.swift` | SQLiteVec | in-memory brute force |

## Testing

- Pure logic is exhaustively unit-tested (clustering order-invariance, chunking, budgeting,
  RRF/MMR ordering, memory distill/prune, voice state machine, sentence chunking).
- Guided-generation and pipelines are tested with **mock gateways** (scripted JSON) — no
  device needed.
- `NetworkAuditTests` proves zero network calls (the privacy guarantee).
- Device-only surfaces (mic, real speech, on-device model quality, thermals) are validated
  via [DEVICE_TEST_CHECKLIST.md](https://github.com/RW2523/EchoMind/blob/main/AppStore/DEVICE_TEST_CHECKLIST.md).

## Conventions

- No force unwraps; no singletons (except `AppDependencies`); files < ~300 lines.
- Value types/protocols are `nonisolated` (the project defaults actor isolation to
  `MainActor`).
- New Swift files in existing folders are picked up automatically (synchronized groups) —
  the `.xcodeproj` is never hand-edited.
