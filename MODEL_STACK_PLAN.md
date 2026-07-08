# Model Stack v1 — build plan

Reconciles the agreed model stack (table below) with what's already shipped on
`v2`, and sequences the remaining work. Principle unchanged: **measure-then-ship**
(every retrieval/quality change gates on the eval harness) and **one seam per
layer** so models are data, not code paths.

## 1. The stack, mapped to reality

| Layer | Choice | Status in EchoMind today | Work remaining |
|---|---|---|---|
| Conversation (default) | Apple Foundation Model | ✅ **Shipped** — `FoundationModelService` behind `RoutingModelGateway` | None |
| Conversation (your own) | Qwen via MLX, 4-bit | ✅ **Code-complete** — `MLXEngine`/`LocalLLMGateway`/Model Manager; dormant until package added | M0 (human) + M1 catalog row |
| Live transcript | SpeechTranscriber / SpeechAnalyzer | ✅ **Shipped in V1** | None |
| Speaker labels (optional) | FluidAudio | ❌ Not started (= V2_PLAN P20) | M3 spike, kill-criterion |
| RAG embeddings | EmbeddingGemma 308M (~200 MB) | ⚠️ Currently `NLEmbeddingService` (0 MB, works, eval-gated ≥ 0.6) | M2 — the big quality lever |
| RAG vector store | sqlite-vec | ⚠️ Currently brute-force vDSP cosine (sub-ms at our scale) | **M4 — deferred, trigger-based** |

Two rows I recommend adjusting:

- **Qwen version**: the catalog currently pins `Qwen2.5-1.5B-Instruct-4bit`
  (proven on mlx-community). Adding the newer 2B-class Qwen as a second row is a
  one-line catalog change — but verify the exact `mlx-community/...` repo id
  exists at that moment; model naming drifts. Keep the 1.5B row for older iPhones.
- **sqlite-vec**: recommend **defer**. Brute-force vDSP over pre-normalized
  vectors is already sub-millisecond at realistic personal scale (thousands of
  chunks). sqlite-vec buys speed only around ~50k–100k vectors, and costs a C
  package, a storage migration, and a second copy of every embedding. Adopt when
  a real corpus proves the need, not before. Trigger: chunk count > 50k **or**
  measured `topK` latency > 10 ms on device.

## 2. Milestones

### M0 — Human unlock (~30 min, blocks M1)
1. Xcode ▸ File ▸ Add Package Dependencies ▸ `ml-explore/mlx-swift-examples`
   → products **MLXLLM**, **MLXLMCommon** (steps in PACKAGES.md).
2. On a physical iPhone: Settings ▸ On-Device AI ▸ download Qwen, flip Apple
   Intelligence **off**, confirm chat + summaries still answer (routed local).
3. That's the whole unlock — everything downstream is already wired.

### M1 — Catalog refresh (same day, trivial)
- Add the newer Qwen 2B-class row to `LocalModelCatalog` (verify repo id on
  mlx-community first); keep 1.5B as the older-device default.
- Gate: model downloads, loads, and answers a guided-JSON generation on device.

### M2 — EmbeddingGemma embeddings (~3–5 days) ← the highest-value item
Replaces NLEmbedding as the retrieval brain. Plan:
- `GemmaEmbeddingService: EmbeddingService` — runs EmbeddingGemma-308M via MLX
  (`MLXEmbedders`), behind the same `#if canImport` guard as the LLM. ~200 MB,
  downloaded through the existing Model Manager + consent flow (new catalog
  entry with `kind: .embedding`).
- Dimension changes (NLEmbedding ≠ Gemma dims) → the existing
  `embeddingDimension` + rebuild-index flow already handles the switch; wire the
  swap to trigger a rebuild prompt.
- **Ship gate (eval harness):** Gemma must beat NLEmbedding on the handbook
  suite (and a new 10-query multi-domain suite) — otherwise documented no-ship,
  NLEmbedding stays. Score recorded in the commit message.
- License note: Gemma terms are use-restricted (not Apache) — surface attribution
  in Settings ▸ About, and it must remain user-initiated download (already is).
- Fallback ladder: Gemma downloaded → use it; else NLEmbedding (never a dead app).

### M3 — FluidAudio speaker labels (~2–3 day spike, after P17 audio retention)
- Third-party package (human adds in Xcode, same ritual as MLX).
- `DiarizationService` protocol seam; FluidAudio conformer behind `#if canImport`.
- Depends on P17 (audio retention, approved on-by-default) landing first so the
  spike can run against real recorded meetings.
- **Kill criterion (from V2_PLAN):** if label accuracy embarrasses on 3 real
  multi-speaker recordings, park it — it's a spike, not a commitment.

### M4 — sqlite-vec (deferred)
- Not scheduled. Revisit when the trigger fires (50k chunks / >10 ms topK).
- If adopted: keep `VectorSearch` as the seam; sqlite-vec becomes an
  implementation behind it, embeddings mirrored into a sidecar `.sqlite`.

## 3. Sequence

```
M0 (you, 30 min) ──► M1 (same day) ──► M2 EmbeddingGemma (eval-gated)
                                          │
P17 audio retention (next build phase) ──► M3 FluidAudio spike
                                          M4 sqlite-vec: dormant, trigger-based
```

## 4. Risks

| Risk | Mitigation |
|---|---|
| mlx-community repo ids drift (Qwen naming) | Verify id at M1; catalog is data — fix is a row edit |
| EmbeddingGemma loses to NLEmbedding on eval | No-ship documented; zero-download NLEmbedding stays default |
| Gemma license terms | User-initiated download + attribution screen; weights never bundled |
| Diarization accuracy | Kill-criterion spike (unchanged from V2_PLAN) |
| Vector-store premature optimization | M4 explicitly trigger-based, not scheduled |
