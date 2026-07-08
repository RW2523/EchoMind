# Third-party packages

V1 shipped with **zero** third-party dependencies. V2.1 relaxes that for exactly
one purpose — an on-device LLM so full AI works with Apple Intelligence off — under
decision gate **G1** (approved 2026-07-07). Every addition here is: on-device only,
no telemetry, vetted, and behind a swappable seam.

## MLX Swift (Phase 14)

- **Repo:** https://github.com/ml-explore/mlx-swift-examples
- **Products to add:** `MLXLLM`, `MLXLMCommon` (transitively pulls in `mlx-swift`)
- **Why:** Apple's own Metal-backed array/inference framework. Runs 4-bit quantized
  small LLMs (Qwen2.5-1.5B etc.) on the Neural Engine/GPU. No server, no telemetry.
- **License:** MIT.

### One-time Xcode setup (must be done by a human — CC cannot edit `.xcodeproj`)

1. Open `EchoMind.xcodeproj` in Xcode.
2. **File ▸ Add Package Dependencies…**
3. Paste the repo URL above. Dependency Rule: **Up to Next Major** from the latest release.
4. Add to the **EchoMind** app target. Select products **MLXLLM** and **MLXLMCommon**.
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

## Where the seam lives

- `Core/AI/Local/LocalLLMEngine.swift` — the protocol (messages → text).
- `Core/AI/Local/MLXEngine.swift` — the only file importing MLX (`#if canImport`).
- `Core/AI/Local/LocalLLMGateway.swift` — adapts any engine to `ModelGateway`.
- `Core/AI/Local/GuidedJSON.swift` — emulates guided generation via `@Generable`'s
  own `GenerationSchema` + `GeneratedContent(json:)`.
- `Core/AI/FeatureRouter.swift` — Apple-FM vs local vs retrieval-only decision.

Swapping engines (e.g. llama.cpp) = one new `LocalLLMEngine` conformer. Nothing above changes.
