# Voice Conversation RAG Agent — build plan

A hands-free, fully on-device voice agent over the existing conversational RAG:
speak a question → the agent decides whether to consult your knowledge → answers
out loud, sentence-by-sentence, interruptible mid-answer. Same principles as
everything else in V2: **one seam per component, first-party floor under every
third-party upgrade, measure-then-ship.**

## 1. The stack, mapped to reality

| Stage | Component | Status in EchoMind | SDK verified? |
|---|---|---|---|
| Listen (STT) | SpeechTranscriber (streaming) | ✅ **Shipped** — live transcription pipeline (V1) | ✅ in use |
| Turn-taking (VAD) | `SpeechDetector` | ❌ New — but it's a `SpeechModule` that plugs into the **same `SpeechAnalyzer`** we already run | ✅ iOS 26 SDK |
| Think (agent) | AFM / Qwen via `RoutingModelGateway` | ✅ Shipped/code-complete — but **non-streaming**; streaming is the new work | ✅ `streamResponse` exists |
| Retrieval | Hybrid RAG (NLEmbedding/Gemma + BM25 + RRF + MMR) | ✅ Shipped | — |
| Speak (TTS) | **Kokoro-82M** (`af_heart`) | ❌ New package. **Floor: `AVSpeechSynthesizer`** (first-party, on-device, zero download) so the agent works end-to-end before Kokoro lands | ✅ AVFAudio |
| Echo cancellation | AVAudioEngine voice processing | ❌ New config on the existing engine. **Bonus:** emits `SpeechActivityStarted/Ended` events — a hardware-assisted barge-in signal | ✅ AVAudioIONode |

Two-thirds of the pipeline already exists. The genuinely new pieces: a streaming
seam on the gateway, a TTS seam, VAD endpointing, and the orchestrating state
machine.

## 2. Architecture

### New seams (each = protocol + first-party default + optional upgrade)

1. **`StreamingModelGateway`** — `stream(instructions:prompt:) -> AsyncThrowingStream<String>`
   as an *optional capability protocol* alongside `ModelGateway` (not a breaking
   change). Apple FM: `session.streamResponse`. MLX: per-token callback in
   `MLXLMCommon.generate`. Routing gateway forwards to whichever backend it picked;
   backends without streaming fall back to one chunk (the full response) — the
   pipeline downstream doesn't care.

2. **`SpeechSynthesizing`** — `speak(text) / stop() / events(didFinishUtterance)`.
   - `SystemSpeechSynthesizer` (AVSpeechSynthesizer): first-party floor, ships day 1.
   - `KokoroSynthesizer` behind `#if canImport(...)`: the warm `af_heart` voice.
     Weights (~80–330 MB depending on quantization) go through the **existing Model
     Manager**: new `ModelKind.tts` catalog row, same consent flow, same downloader.
     Package candidates (verify at add time — this space moves fast): FluidAudio's
     TTS module (already on our package list for diarization — one package, two
     features) or mlx-audio's Swift Kokoro. Pick whichever loads on iOS cleanly.

3. **`TurnDetecting` (VAD)** — wraps `SpeechDetector` added as a second module on
   the already-running `SpeechAnalyzer`; emits `.speechStarted` / `.speechEnded`.
   Endpoint rule: speech ended + ~700 ms hold + non-empty transcript → end of turn.
   Fallback floor: a volatile-transcript quiescence timer (works even if
   SpeechDetector misbehaves — same signal we already surface in the live UI).

4. **`VoiceSessionController`** — the heart; a pure-logic state machine:

   ```
   idle → listening → thinking → speaking → listening → …
                ▲          │           │
                └──────────┴───────────┘  barge-in / cancel from ANY state
   ```

   Rules: partial transcript renders live while listening; end-of-turn freezes the
   utterance and calls RAG `ask(question, history:)` (voice turns join the same
   `ChatTurn` history as typed chat — one conversation, two input modes); streamed
   tokens go through a **sentence chunker** that hands complete sentences to TTS
   (first audio ~1 s in, while the rest still generates); mic stays open during
   `speaking` — user speech (VAD or voice-processing activity event) **stops TTS,
   cancels generation, transitions to listening**. Everything cancellable at every
   await point.

5. **Sentence chunker** — pure function: token stream → complete-sentence stream
   (split on `.?!` + abbreviation guards). Exhaustively unit-testable.

### Echo cancellation (required for barge-in)

`AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` + `.playAndRecord`
session — the mic stream is echo-cancelled so the transcriber doesn't hear
Kokoro's voice as user speech. This touches `AudioEngineManager` behind a
`voiceMode` flag so the plain recording path is untouched. **Risk:** voice
processing changes the input format/gain; the tap must re-read the format (our
tap already does).

### Agentic retrieval decision

The current pipeline retrieves every turn and lets the model decide relevance
(`usedProvidedContext`). Retrieval is ~50–150 ms — cheap enough that skipping it
saves little and risks ungrounded answers. **Decision: keep retrieve-always for
v1** of the voice agent; revisit an LLM "should I retrieve?" pre-decision only if
the measured latency budget demands it. (The "agentic" part users actually feel is
grounded-vs-chat behavior + interruption, both of which we have/get.)

## 3. Latency budget (device, target iPhone 15 Pro)

| Stage | Target |
|---|---|
| End-of-speech → end-of-turn decision | ≤ 0.8 s (VAD hold) |
| Retrieval (embed + hybrid + MMR) | ≤ 0.2 s |
| First streamed sentence from AFM | ≤ 1.0 s |
| TTS synthesis of sentence 1 (Kokoro) | ≤ 0.4 s |
| **Speech-end → first audio out** | **≤ 2.4 s; kill-criterion 3.5 s** |

If the full-duplex loop can't beat 3.5 s on device, ship push-to-talk (still a
wow) and keep hands-free behind a debug flag until it does.

## 4. Phases

### V1 — Push-to-talk voice ask — SHIPPED (device-verify pending)
Mic button in Ask → hold/tap to talk (SpeechTranscriber) → release/auto-stop →
existing `ask()` → answer spoken via **AVSpeechSynthesizer** + shown as a normal
chat bubble. Includes: `SpeechSynthesizing` seam + system implementation,
`VoiceSessionController` (states: idle/listening/thinking/speaking, no barge-in
yet), voice UI (mic button, listening indicator, speaking indicator, tap-to-stop).
**Gate:** voice question → grounded spoken answer end-to-end. DONE: `SpeechSynthesizing`
+ `SystemSpeechSynthesizer`, `VoiceInput` + `LiveVoiceInput`, `VoiceSessionController`
state machine (listen→think→speak, cancel from any state), Ask mic button + live
listening strip. Voice turns join the same chat history/bubbles as typed chat.
6 controller tests (full turn, empty transcript, nil answer, start-failure, cancel-
during-speaking); 204 total green. Device-verify mic capture + spoken output next.

### V2 — Streaming + sentence-by-sentence speech
`StreamingModelGateway` (Apple FM + MLX), sentence chunker, RAG streaming path
(`askStreaming` alongside `ask`), TTS consumes sentences as they arrive.
**Gate:** first audio ≤ 2.4 s after end of turn (measured, logged in TESTLOG.md).

### V3 — Hands-free + barge-in (device-only validation)
`SpeechDetector` VAD endpointing (auto end-of-turn), voice-processing echo
cancellation, mic-open-while-speaking, interruption cancels TTS + generation.
**Gate:** 10-turn hands-free conversation; barge-in works with TTS at full volume;
no self-transcription of the agent's own voice.

### V4 — Kokoro TTS upgrade (needs package + human)
`KokoroSynthesizer` behind `#if canImport`, `ModelKind.tts` catalog row +
Model Manager section ("Voice"), `af_heart` default, AVSpeech remains the floor
whenever weights aren't downloaded. **Gate:** A/B against AVSpeech on device;
Kokoro ships only if it's clearly better *and* sentence latency ≤ 0.4 s.

## 5. Testing

- State machine: every transition + cancellation path, mock STT/VAD/TTS/gateway
  (pure logic — simulator-green).
- Sentence chunker: golden cases (abbreviations, decimals, ellipses, no-terminator
  flush-on-finish).
- Streaming gateway: mock backend emits token bursts → assembled text matches;
  cancellation stops consumption.
- Echo cancellation, real VAD timing, Kokoro quality, latency budget: **device
  matrix rows** (TESTLOG.md), like audio/diarization before them.

## 6. Human prerequisites

1. Nothing for **V1–V3 scaffolding** — first-party APIs only. (V3 barge-in
   *validation* needs a physical device, as does real Kokoro.)
2. **V4:** add the TTS package in Xcode (candidates in PACKAGES.md once chosen) +
   host/verify the Kokoro weights repo id.
3. A quiet room and a loud room for the barge-in device test.

## 7. Risks

| Risk | Mitigation |
|---|---|
| Kokoro Swift ports immature on iOS | AVSpeechSynthesizer floor ships first; Kokoro is an upgrade, not a dependency |
| Voice processing breaks transcription quality | `voiceMode` flag isolates it; plain path untouched; device A/B before default-on |
| VAD endpointing too eager/laggy | Sensitivity option + transcript-quiescence fallback; hold time tunable |
| Latency budget missed on older devices | Kill-criterion → push-to-talk mode remains the shipped experience |
| TTS speaks over transcriber (no barge-in without echo-cancel) | V3 gate explicitly tests self-transcription; until then half-duplex (mic paused while speaking) |
