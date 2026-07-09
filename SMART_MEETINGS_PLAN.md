# Smart Meetings — build plan

Three features that turn EchoMind from "record & search" into a **meeting
intelligence system**, all fully on-device:

1. **Auto Report** — every recorded session automatically produces a report:
   summary, decisions, extracted action items (with owners), risks, questions.
2. **Smart Grouping** — meetings are AI-classified and clustered so similar-concept
   meetings ("Weekly Standup", "Project Phoenix", "1:1s") group together, even when
   worded differently.
3. **Total Recall** — reports and RAG answers carry the context of *all previous
   meetings*: a persistent, evolving memory layer ("last week you decided X; this
   week it changed to Y").

Principles unchanged: seams + first-party floor, everything through the routed
gateway (Apple FM today, local Qwen when unlocked), every token through
`TokenBudgeter`, measure-then-ship.

## 0. What we already have (this is why the plan is cheap)

| Need | Already built | Gap |
|---|---|---|
| Summary + action items schema | `MeetingSummary` (@Generable: overview, keyDecisions, actionItems+owner, risks, openQuestions) + `MapReduceSummarizer` | It's **manual** (button in detail) — needs auto-trigger + retry + richer surfacing |
| Category storage | `Session.tags: [String]` in schema since V1 | Nothing writes it — needs a classifier |
| Similarity signal | Per-chunk embeddings stored per session (`sourceId`) | Mean-pool → session vector; clustering logic |
| Cross-session retrieval | Hybrid RAG over ALL chunks | No *memory document*; reports don't see prior meetings |
| Token discipline | `TokenBudgeter`, 4096 floor | Budgets for memory/context injection |
| Background AI | Routed gateway + guided JSON (works with local LLM too) | — |

## 1. Architecture — three new seams

### A. `ReportPipeline` (auto report)
```
stopTapped → finalize → index (exists)
          → ReportPipeline.generate(sessionId)          [background Task]
              ├─ summarizer.summarize(segments)         (exists)
              ├─ classifier.label(session)              (new, feature B)
              ├─ memory.distill(from: report)           (new, feature C)
              └─ persist summaryJSON + tags; mark reportState
```
- `reportState` per session: `.pending → .ready / .failed` (additive column,
  lightweight migration). Failed/interrupted reports retry on next app-active or
  when the session detail opens ("Generating report…" shimmer instead of a button).
- Tier B devices (no generator): state `.unavailable`, manual button remains.
- Action-item **check-off**: completion is user state, not model output — stored in
  an additive `actionStatesJSON` column keyed by stable action-item index; never
  round-trips through the model.
- Surfacing: report card at the top of SessionDetail (already exists, gets richer:
  action-item checkboxes, share/export of report markdown), Home "Latest report"
  card, and a badge on Sessions rows until first viewed.

### B. `MeetingClassifier` + `SessionClusterer` (smart grouping)
Two cooperating layers — label *names* come from the LLM, label *stability* comes
from math:

1. **`SessionClusterer` (pure, exhaustively testable — the heart).**
   - Session vector = L2-normalized mean of its chunk embeddings (already stored;
     zero extra inference).
   - Greedy threshold clustering: new session joins the nearest existing cluster if
     cosine ≥ τ (start τ=0.55, tuned via eval fixtures), else starts a new cluster.
   - Deterministic, order-stable, incremental (one session at a time, no O(n²)
     re-cluster on every launch; full re-cluster only on "rebuild index").
2. **`MeetingClassifier` (guided generation, one small call per session).**
   - Input: report overview + top terms (NOT the whole transcript — ~200 tokens).
   - Output (@Generable): `category` (short noun phrase) + up to 3 topic tags.
   - **Canonical naming rule:** if the session joined an existing cluster, it
     *inherits the cluster's existing category name* (prompt shows the model the
     current name; it may keep or refine only if clearly wrong) — this is what stops
     "Weekly Sync" / "Team Weekly" / "Standup" fragmenting into three groups.
   - Persisted into `tags` (slot 0 = category, rest = topics). No migration.
3. **UI:** Sessions tab gains a grouped mode — category sections with counts,
   horizontally scrollable filter chips, colored category dots (hash of name →
   palette). Home shows "Your meeting types" chips. Search still flat.

### C. `MeetingMemory` (total recall)
Two complementary mechanisms — **distilled memory** (compact, always injected) and
**episodic retrieval** (targeted, per question):

1. **Distilled memory document** — `MemoryFact` store (additive @Model:
   `id, kind (person|project|decision|preference|recurring), text, sourceSessionId,
   updatedAt`). After each report, one guided call: "given this report and these
   existing facts, return facts to ADD / UPDATE / RETIRE" → apply. Bounded: max ~60
   facts / ~800 tokens; oldest-retired first. This is the app's long-term brain —
   compact enough to inject *whole* into prompts.
2. **Report continuity** — when generating a report, retrieve top-k chunks from
   *prior sessions in the same cluster* + relevant memory facts → summarizer's
   reduce call gains a `Previous context:` block and the schema gains
   `continuityNotes: [String]` ("Follow-up from last meeting: …"). Budget: ≤600
   tokens of prior context, packed by `TokenBudgeter`, dropped first on overflow.
3. **RAG injection** — `RAGPipeline.ask/askStreaming` prepend relevant memory facts
   (top-m by embedding similarity to the query, ≤300 tokens) alongside retrieved
   chunks. Voice + typed + reports all share the same brain.
4. **Privacy/lifecycle** — facts are on-device rows: covered by wipe-all, exported
   with data export, count shown in Settings ▸ Storage; per-fact delete list in
   Settings ("What EchoMind remembers") for transparency — a wow feature in itself.

## 2. Token budgets (4096 floor, per call)

| Call | Inputs | Budget |
|---|---|---|
| Report reduce (exists) | transcript windows | unchanged |
| + continuity block | prior-cluster chunks + facts | ≤600 (dropped first) |
| Classifier | overview + terms + cluster name | ≤350 in / ~80 out |
| Memory distill | report + current facts | ≤1400 in / ~300 out |
| RAG memory preamble | top-m facts | ≤300 (dropped before chunks) |

## 3. Phases

### R1 — Auto Report (2–3 days)
`ReportPipeline` + `reportState`/`actionStatesJSON` columns + auto-trigger on stop
+ retry-on-active + report UI (checkboxes, share, Home latest-report card).
**Gate:** stop a recording → report appears without any tap (mock-gateway
integration test + simulator run); failed generation retries and never blocks
saving the session; Tier B keeps the manual path.

### R2 — Smart Grouping (2–3 days)
`SessionClusterer` (pure) + `MeetingClassifier` (guided) + canonical-name rule +
grouped Sessions UI + filter chips.
**Gate:** clustering eval fixture — 12 synthetic sessions across 4 known groups
cluster correctly (≥10/12) with stable labels across insertion orders; UI groups
render; re-run with sessions inserted in reverse order → same clusters.

### R3 — Total Recall (3–4 days)
`MemoryFact` store + distiller + report continuity (`continuityNotes`) + RAG/voice
memory preamble + Settings "What EchoMind remembers" + wipe/export coverage.
**Gate:** scripted two-meeting scenario (mock gateway): meeting 2's report
references meeting 1's decision; asking "what did we decide about X?" answers from
memory even after chat history is cleared; wipe-all leaves zero facts.

Order matters: R1 produces the reports that R2 classifies and R3 distills.

## 4. Testing

- **Pure cores first:** cluster math (thresholds, incremental stability, order
  invariance), fact-merge apply logic (add/update/retire, byte-budget eviction),
  action-state round-trip — all deterministic unit tests.
- **Mock-gateway integration:** scripted JSON outputs drive report → classify →
  distill end-to-end without Apple FM (works in CI/simulator, same pattern as
  existing guided-JSON tests).
- **Eval discipline:** clustering fixture ships as a test (like RetrievalEval);
  τ threshold recorded in the commit message when tuned.
- **Schema:** additive columns only (`reportState`, `actionStatesJSON`, new
  `MemoryFact` table) → SwiftData lightweight migration; migration smoke test on a
  fixture store.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Auto-generation drains battery after long meetings | Report runs once, backgrounded, deferred under thermal `.serious`+ (FeatureRouter already knows) |
| Category fragmentation ("Standup" vs "Weekly Sync") | Cluster-first, name-second canonical rule; math owns grouping, model only names it |
| Memory doc drifts wrong / stale facts poison answers | Facts carry provenance (source session), user-visible + deletable list, retire pass every distill |
| Context injection blows the 4096 window | Hard budgets, packed by TokenBudgeter, memory dropped before chunks — grounded answering always wins |
| Tier B devices (no generator) | Reports/classification queue until AI is available; app stays fully usable |

## 6. Sequence

```
R1 Auto Report ──► R2 Smart Grouping ──► R3 Total Recall
     (reports)        (labels clusters)     (memory across all)
```
~7–10 focused days, each phase independently shippable and demo-able.
