<div align="center">

# EchoMind

### Private meeting memory for your iPhone

**Record → transcribe → auto-report → ask.** All on-device. Nothing ever leaves your iPhone.

[![CI](https://github.com/RW2523/EchoMind/actions/workflows/ci.yml/badge.svg)](https://github.com/RW2523/EchoMind/actions/workflows/ci.yml)
![Platform](https://img.shields.io/badge/iOS-26-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![UI](https://img.shields.io/badge/SwiftUI%20%2B%20SwiftData-blue)
![Tests](https://img.shields.io/badge/tests-309%20passing-brightgreen)
![Network](https://img.shields.io/badge/network-zero-success)
![Privacy](https://img.shields.io/badge/data%20collected-none-success)

</div>

---

EchoMind turns every meeting into searchable memory — without sending a single word to
the cloud. Record on your iPhone and it transcribes live; the moment you stop, Apple
Intelligence writes a clean report (summary, decisions, action items) and the session
names itself. Meetings are grouped by topic automatically, a long-term memory builds
across every meeting, and you can ask questions by text or voice.

## Screenshots

| Home | Sessions (grouped) | Ask | Report | Memory |
|---|---|---|---|---|
| ![Home](https://github.com/RW2523/EchoMind/blob/main/AppStore/screenshots/01-home.png) | ![Sessions](https://github.com/RW2523/EchoMind/blob/main/AppStore/screenshots/02-sessions.png) | ![Ask](https://github.com/RW2523/EchoMind/blob/main/AppStore/screenshots/03-ask.png) | ![Report](https://github.com/RW2523/EchoMind/blob/main/AppStore/screenshots/04-report.png) | ![Memory](https://github.com/RW2523/EchoMind/blob/main/AppStore/screenshots/05-memory.png) |

## Features

- 🎙️ **Live transcription** — on-device speech-to-text (SpeechAnalyzer), keeps recording while the screen is locked.
- 📝 **Auto reports** — summary, key decisions, and check-off action items generated automatically when you stop — and the session **names itself** from what was discussed.
- ✅ **Reminders export** — send a report's action items to Apple Reminders with one tap.
- 🔐 **App lock** — optional Face ID / Touch ID gate on opening the app.
- 🗂️ **Smart grouping** — meetings are clustered by concept and AI-labeled, so similar meetings organize themselves.
- 🧠 **Total recall** — a durable cross-session memory of people, projects, and decisions, used to answer with context from *every* past meeting.
- 🔗 **Report continuity** — new reports reference prior related meetings ("follow-up on last week's decision…").
- 💬 **Ask anything** — chat with your meetings and documents (hybrid RAG), grounded with sources — by text or voice.
- 🎧 **Voice mode** — a full-screen, hands-free conversation (ChatGPT/Grok-style): a living orb, live captions, tap-to-interrupt. Streams the reply sentence-by-sentence so it speaks instantly; upgrades to the warm Kokoro voice when that pack is installed.
- ▶️ **Tap-to-play** — retained audio with a scrubber; tap any transcript line to jump there.
- 📄 **Import** — PDFs and notes searchable alongside your meetings.
- 🔒 **Private by design** — 100% on-device, no account, no tracking, **zero network calls** (enforced by a test). Export or delete everything anytime.

## Privacy

EchoMind collects **no data** and makes **no network requests** in normal use. Transcription
and all AI (summaries, grouping, memory, answers) run on the device via Apple's
SpeechAnalyzer and Apple Intelligence. Recordings, transcripts, and notes live only in the
app's protected, sandboxed storage. This is verified by `NetworkAuditTests` in CI.
See the [privacy policy](https://github.com/RW2523/EchoMind/blob/main/AppStore/PRIVACY_POLICY.md).

## Architecture

MVVM + protocol-based services, composed once in `AppDependencies`.

```
Features/<Feature>/{View, ViewModel}          SwiftUI + @Observable view models
Core/Audio        AVAudioEngine capture, interruptions, retained audio
Core/Transcription SpeechAnalyzer behind TranscriptionService
Core/AI           RoutingModelGateway (Apple FM ▸ local LLM ▸ retrieval-only),
                  TokenBudgeter, Summarizer, ReportPipeline, MeetingClassifier,
                  MemoryDistiller, MeetingContinuityService, SessionTitler
Core/RAG          TextChunker, embeddings, VectorSearch, BM25, RRF, MMR,
                  RAGPipeline, SessionClusterer, VectorStore, RetrievalBenchmark
Core/Voice        VoiceSessionController, SpeechSynthesizing, SentenceChunker,
                  TurnEndpointer, SpeechOnsetDetector
Core/Security     AppLockAuthenticating (Face ID / Touch ID)
Core/Integrations ReminderExporting (EventKit)
Core/Storage      SwiftData @Model + @ModelActor repositories (Sendable snapshots)
Models/           pure value types
```

Design principles: **every service is a protocol with one implementation**; all AI goes
through a single routed gateway; **every optional third-party engine sits behind exactly one
`#if canImport` file** with a first-party floor, so the app builds and ships with zero
packages. Details on the [Architecture](Architecture) page.

## Requirements

- Xcode 26+, iOS 26 SDK
- An **Apple-Intelligence-capable iPhone** for on-device AI summaries/answers (transcription works more broadly)
- Swift 6, strict concurrency

## Build & run

```bash
git clone https://github.com/RW2523/EchoMind.git
open EchoMind/EchoMind.xcodeproj    # then ⌘R on a simulator or device
```

Command line:

```bash
# Build
xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
# Test (run serially — CoreSimulator dislikes parallel here)
xcodebuild -scheme EchoMind -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:EchoMindTests -parallel-testing-enabled NO test
```

**309 tests** cover the pure logic exhaustively — clustering (order-invariant), chunking,
token budgeting, memory distillation, RAG fusion, the voice state machine, action-item
completion, the app-lock state machine, and the zero-network audit. GitHub Actions runs the
full suite on every push. Anything touching mic/speech/on-device models is device-only.

## Status

| Area | Status |
|---|---|
| Live transcription, sessions, import, RAG chat/voice, reports, grouping, memory | ✅ Shipped |
| AI session titles, Reminders export, Face ID app lock, immersive Voice mode | ✅ Shipped |
| Verified live (grounded RAG with real generation, in-simulator) | ✅ |
| Local LLM (Qwen/MLX), EmbeddingGemma, sqlite-vec, Kokoro TTS, diarization (FluidAudio) | 🔌 Code-complete behind `#if canImport` — add packages to enable |
| Device validation of the record/voice loop | ⏳ [Checklist](https://github.com/RW2523/EchoMind/blob/main/AppStore/DEVICE_TEST_CHECKLIST.md) — needs a physical iPhone |
| App Store submission | ⏳ Build-ready; needs paid Developer Program — see [TESTFLIGHT.md](https://github.com/RW2523/EchoMind/blob/main/AppStore/TESTFLIGHT.md) |

## Optional on-device model packs (1.1)

Adding a Swift package lights up a downloadable model, each isolated behind one file:

| Pack | Package | Enables |
|---|---|---|
| Local LLM | `ml-explore/mlx-swift-examples` (MLXLLM) | Full AI with Apple Intelligence off |
| Embeddings | MLXEmbedders | EmbeddingGemma retrieval |
| Diarization | `FluidInference/FluidAudio` | Speaker labels |
| Voice | FluidAudio TTS / Kokoro | Warm "af_heart" voice |

Steps in [PACKAGES.md](https://github.com/RW2523/EchoMind/blob/main/PACKAGES.md).

## Documentation

- **[User Guide](User-Guide)** — how to use every feature
- **[Architecture](Architecture)** — how the app is built
- **[FAQ](FAQ)** — common questions
- Design docs (in the repo): [PLAN.md](https://github.com/RW2523/EchoMind/blob/main/PLAN.md), [SMART_MEETINGS_PLAN.md](https://github.com/RW2523/EchoMind/blob/main/SMART_MEETINGS_PLAN.md), [VOICE_AGENT_PLAN.md](https://github.com/RW2523/EchoMind/blob/main/VOICE_AGENT_PLAN.md), [MODEL_STACK_PLAN.md](https://github.com/RW2523/EchoMind/blob/main/MODEL_STACK_PLAN.md)

## License

© 2026 AJACE. Source-available for personal evaluation and learning — no
redistribution or commercial use without permission. See the
[LICENSE](https://github.com/RW2523/EchoMind/blob/main/LICENSE).
