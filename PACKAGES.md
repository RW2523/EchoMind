# Third-party packages

V1 shipped with **zero** third-party dependencies. V2.1 relaxes that for exactly
one purpose — an on-device LLM so full AI works with Apple Intelligence off — under
decision gate **G1** (approved 2026-07-07). Every addition here is: on-device only,
no telemetry, vetted, and behind a swappable seam.

## MLX Swift (Phase 14)

- **Repo:** https://github.com/ml-explore/mlx-swift-examples
- **Products to add:** `MLXLLM`, `MLXLMCommon`, **`MLXEmbedders`** (transitively pulls in `mlx-swift`)
- **Why:** Apple's own Metal-backed array/inference framework. Runs 4-bit quantized
  small LLMs (Qwen2.5-1.5B etc.) on the Neural Engine/GPU, and — via `MLXEmbedders`
  — the EmbeddingGemma-300M retrieval embedder (M2). No server, no telemetry.
- **License:** MIT (EmbeddingGemma weights carry Gemma terms — user-initiated
  download, attribution shown in-app; never bundled).
- **What lights up when added:** `MLXEngine` (chat), `MLXModelDownloader`, and
  `GemmaEmbeddingService` (embeddings) — all behind `#if canImport`. Reconcile
  `MLXEngine.swift` / `GemmaEmbeddingService.rawEmbed` if the MLX API drifted.

### One-time Xcode setup (must be done by a human — CC cannot edit `.xcodeproj`)

1. Open `EchoMind.xcodeproj` in Xcode.
2. **File ▸ Add Package Dependencies…**
3. Paste the repo URL above. Dependency Rule: **Up to Next Major** from the latest release.
4. Add to the **EchoMind** app target. Select products **MLXLLM**, **MLXLMCommon**, and **MLXEmbedders**.
5. Build once (`⌘B`). This compiles `MLXEngine.swift` (guarded by `#if canImport(MLXLLM)`).
   Until this step, the app builds fine without the engine — the local path just
   reports "model not ready".
6. Real inference only works on a **physical device** (Metal + enough RAM); the
   Simulator can build the code but not run the model.

### Networking note

The engine downloads weights from the pinned Hugging Face repo
(`mlx-community/…`) on first load — the **only** network call in the app, gated by
an explicit consent screen (Phase 15). The network-audit test is extended with a
downloader-only allowlist; nothing else may hit the network.

## FluidAudio (M3 — speaker diarization)

- **Repo:** https://github.com/FluidInference/FluidAudio
- **Product to add:** `FluidAudio`
- **Why:** on-device speaker diarization ("who spoke when") over a retained
  recording. Core ML models, no server. Open source.
- **License:** open source (verify the current license before shipping).
- **What lights up when added:** `FluidAudioDiarizer` (behind `#if canImport(FluidAudio)`).

### Xcode setup

1. **File ▸ Add Package Dependencies…** → paste the repo URL → add product
   **FluidAudio** to the **EchoMind** target. Build once.
2. Diarization is **user-initiated** (Session ▸ ⋯ ▸ *Identify Speakers*), shown only
   when the package is linked **and** the session has retained audio (needs P17 on).
3. Device-only for real results; the Simulator builds the code but has no audio input.
4. If the FluidAudio API drifted, reconcile in `FluidAudioDiarizer.normalize` /
   `diarize` — the single `#if`-guarded touch point. Audio decode + 16 kHz-mono
   resample is done locally and is package-independent.

### Kill criterion

Diarization is a **spike, not a commitment**: if label accuracy embarrasses on 3
real multi-speaker recordings, park the feature (hide the action) — the seam and
tests stay, no other code depends on it.

## sqlite-vec (M4 — vector store, OPTIONAL / scale only)

- **Repo:** https://github.com/asg017/sqlite-vec (Swift Package distribution)
- **Product to add:** `SQLiteVec`
- **Why:** an indexed on-disk vector search. **Not needed at personal scale** —
  brute-force vDSP cosine is sub-millisecond over thousands of chunks. Adopt only
  when the corpus is large (trigger: > 50k chunks **or** measured `topK` > 10 ms).
- **What lights up when added:** `SQLiteVecVectorStore` (behind `#if canImport(SQLiteVec)`).
  Without it, `InMemoryVectorStore` (the brute-force seam) is used — identical
  results, fully tested.
- Reconcile the extension-registration + `vec0` table calls in
  `SQLiteVecVectorStore` if the package API drifted.

## Where the seams live

- `Core/AI/Local/LocalLLMEngine.swift` — LLM protocol (messages → text).
- `Core/AI/Local/MLXEngine.swift` — only file importing `MLXLLM` (`#if canImport`).
- `Core/AI/Local/LocalLLMGateway.swift` — adapts any engine to `ModelGateway`.
- `Core/AI/Local/GuidedJSON.swift` — guided generation via `@Generable`'s
  `GenerationSchema` + `GeneratedContent(json:)`.
- `Core/AI/FeatureRouter.swift` — Apple-FM vs local vs retrieval-only decision.
- `Core/RAG/GemmaEmbeddingService.swift` — only file importing `MLXEmbedders`.
- `Core/Diarization/FluidAudioDiarizer.swift` — only file importing `FluidAudio`.
- `Core/RAG/VectorStore.swift` — vector-store protocol + in-memory default.
- `Core/RAG/SQLiteVecVectorStore.swift` — only file importing `SQLiteVec`.

Each package sits behind exactly one file. Swapping an engine (e.g. llama.cpp) or a
store = one new conformer; nothing else changes.

## Kokoro TTS (Voice Agent V4 — the warm "af_heart" voice)

- **Guard:** `#if canImport(FluidAudioTTS)` — deliberately a **different** module
  from the diarization `FluidAudio` above, so adding the diarization package does
  NOT force-compile the TTS path against a mismatched API. Only linking a TTS
  product activates `KokoroSynthesizer`.
- **Product to add:** the FluidAudio TTS product (verify the exact module name at
  add time — this space moves fast) or an mlx-audio Kokoro package. Then reconcile
  `KokoroSynthesizer.synthesize` — the single package-specific call.
- **Model:** Kokoro-82M (`af_heart`) downloads through the existing Model Manager
  (Settings ▸ On-Device AI ▸ **Voice**), consent-gated. `AVSpeechSynthesizer` stays
  the floor until Kokoro is downloaded + linked, so voice output always works.
- **Seam file:** `Core/Voice/KokoroSynthesizer.swift` (the only `FluidAudioTTS`
  importer); resolution logic in `Core/Voice/SpeechSynthesizerResolver.swift`.
