# EchoMind — Device Test Checklist (Workstream B)

The one thing that must be validated before submitting: the record → transcribe →
report → group → remember → ask loop on a **real iPhone**. Walk this top to bottom,
mark each ✅/❌, and note anything odd. Anything in **P0** must pass to submit.

---

## 0. Setup (do once)

- [ ] **Device:** iPhone that supports **Apple Intelligence** (iPhone 15 Pro or newer / 16 line).
- [ ] iOS updated; **Settings ▸ Apple Intelligence & Siri → ON**, wait until it says *Ready*.
- [ ] Install the app:
  - Easiest for full testing: **Xcode ▸ Run** on the device with a **Debug** build
    (gives you the `--selftest-ask` diagnostic and debug tools).
  - Or **TestFlight** (Release build — closest to what users get; no debug tools).
- [ ] First launch: complete **onboarding**, grant **Microphone** + **Speech Recognition** when asked.
- [ ] **Settings tab ▸ Transcription Language** → confirm your language is selectable and
      selected (this triggers the on-device speech model download if needed — give it
      a minute on Wi-Fi the first time).
- [ ] **Settings ▸ About EchoMind** → version shows **1.0 (1)**, privacy text present.
- [ ] Turn on **Airplane Mode** for one full pass later (P0-8) to prove nothing needs network.

> Diagnostic (Debug build only): launch with `--selftest-ask` from Xcode's scheme
> arguments to auto-run 3 RAG questions and print `[SelfTest]` results to the console —
> a fast sanity check that embeddings + generation work on the device.

---

## P0 — Must pass to submit

### P0-1 · Record a real meeting (core capture)
1. Home ▸ **Start Live Transcript**.
2. Speak naturally for **60–90 seconds** (or play a meeting/podcast near the phone) —
   include at least one **decision** ("let's ship Friday") and one **task with a name**
   ("Priya will send the deck").
3. Watch the screen while recording.
- **Expect:** waveform animates; a running **timer**; words appear as you speak
  (volatile text greys → finalizes into lines). Recording indicator visible.
- ❌ If it says *"transcription isn't available for <locale>"* → the speech model
  isn't installed; finish setup step and retry. Note it.
- Result: ⬜  Notes:

### P0-2 · Stop → auto-report appears (no taps)
1. Tap **Stop**.
2. Go to **Sessions** (or Home ▸ Recent) and open the session you just recorded.
- **Expect:** a **Summary/Report** section shows within a few seconds — a
  **"Generating report…"** state first, then it fills with **Overview, Key Decisions,
  Action Items, Risks, Open Questions**. You did **not** tap "Generate".
- **Check quality:** the decision and the named task you spoke should appear (owner tag
  on the action item if you named someone).
- Result: ⬜  Report quality (1–5): ___  Notes:

### P0-3 · Action items check off (and persist)
1. In the report, tap the circle next to an **action item**.
- **Expect:** it fills blue + strikes through. Leave the screen and come back → still checked.
- Result: ⬜  Notes:

### P0-4 · Audio playback + tap-to-seek
1. In the session detail, find the **Recording** player bar (only if "Keep audio
   recordings" is ON in Settings — it is by default).
2. Tap **play**; then **tap any transcript line**.
- **Expect:** audio plays; tapping a line jumps playback to that moment; scrubber moves.
- Result: ⬜  Notes:

### P0-5 · Ask your meeting (grounded RAG, text)
1. **Ask** tab. Type: *"What did we decide?"* (or ask about the named task).
- **Expect:** an assistant answer that **correctly references what you said**, with a
  **Sources** chip you can tap to see the passage. A short greeting like "Hi" should get
  a friendly conversational reply (not "no knowledge").
- Result: ⬜  Answer correct? ___  Notes:

### P0-6 · Ask by voice (push-to-talk)
1. Ask tab ▸ tap the **mic** button, speak a question, tap the **checkmark** to finish.
- **Expect:** your words transcribe into a question bubble; assistant answers **and
  speaks the answer aloud**; the Q&A also appears as chat bubbles.
- Result: ⬜  Spoken? ___  Notes:

### P0-7 · Interruptions don't lose the recording
1. Start a recording; **lock the screen** for ~20s; unlock.
2. Start another recording and trigger a **phone call** to yourself (or Siri), then return.
- **Expect:** recording **survives screen lock** (background audio) and **pauses/resumes**
  cleanly around the interruption; transcript up to the interruption is saved; no crash.
- Result: ⬜  Notes:

### P0-8 · Fully offline (privacy proof)
1. **Airplane Mode ON.** Record a short session, stop, open the report, ask a question.
- **Expect:** **everything works** — transcription, report, and answers — with no network.
  (This is the whole privacy promise.)
- Result: ⬜  Notes:

### P0-9 · No crashes / clean state
- [ ] No crash across all P0 steps.
- [ ] **Settings ▸ Storage** shows non-zero Sessions/Audio after recording.
- [ ] **Settings ▸ Delete All Data** → confirm → everything (sessions, audio, memory) clears.
- Result: ⬜  Notes:

---

## P1 — Should pass (fix before wide release)

### P1-1 · Smart grouping
1. Record **2 short meetings on the same topic** (e.g. two "project Phoenix" chats) and
   **1 on a different topic**. Open **Sessions**.
- **Expect:** meetings get **category labels** (colored dots) in section headers; the two
  similar ones share a category; **filter chips** appear; tapping a chip filters.
- Result: ⬜  Grouped sensibly? ___  Notes:

### P1-2 · Total recall (memory across meetings)
1. After a few meetings, **Settings ▸ What EchoMind Remembers**.
- **Expect:** a list of **durable facts** (people, projects, decisions) with kind icons.
  Swipe to **forget** one → it disappears.
2. Ask a question whose answer depends on an **earlier** meeting.
- **Expect:** the answer uses that remembered context.
- Result: ⬜  Notes:

### P1-3 · Report continuity
1. Record a **follow-up** to an earlier similar meeting (reference the same project).
2. Open its report.
- **Expect:** a **"Continuing from earlier meetings"** block at the top referencing the
  prior meeting.
- Result: ⬜  Notes:

### P1-4 · Hands-free conversation + barge-in
1. Ask ▸ tap the **hands-free** (waveform) button. Have a back-and-forth **without tapping**.
2. While it's **speaking**, start talking (or tap **✋ Interrupt**).
- **Expect:** it auto-detects when you stop (answers on its own), loops for the next turn,
  and **stops talking when you interrupt**. It should **not** transcribe its own voice.
- **Latency feel:** first audio back within ~2–3s of you finishing. If consistently >3.5s
  or it hears itself, note it → we ship push-to-talk only for 1.0.
- Result: ⬜  Latency ok? ___  Self-transcribes? ___  Notes:

### P1-5 · Document import
1. **Knowledge** tab ▸ **+** ▸ import a **PDF** or text file.
- **Expect:** it imports, appears in the list; **Ask** can now answer from it (grounded,
  with a source pointing to the doc/page).
- Result: ⬜  Notes:

### P1-6 · Permission-denied path
1. iOS Settings ▸ EchoMind ▸ turn **Microphone OFF**. Return to app, try to record.
- **Expect:** a clear message with an **Open Settings** button (no crash, no dead-end).
  Turn it back on.
- Result: ⬜  Notes:

---

## P2 — Polish (nice to confirm)

- [ ] **P2-1 Long recording:** record **60–90 min** (screen on/off). Note any heat, battery
      drain, or slowdown; confirm the report still generates. Thermals shouldn't force-quit.
- [ ] **P2-2 Dynamic Type:** iOS Settings ▸ Accessibility ▸ larger text (near max). Screens
      remain readable, nothing clipped.
- [ ] **P2-3 VoiceOver:** enable briefly; key buttons (Record, Send, mic, action items) are
      labeled and reachable.
- [ ] **P2-4 Reduce Motion:** on → background/animations calm down, no jank.
- [ ] **P2-5 Empty states:** fresh install → Home "No sessions yet", Ask empty state,
      Sessions/Knowledge empty states all read well.
- [ ] **P2-6 Export:** Settings ▸ Export All Data → share sheet produces per-session
      Markdown files that open correctly.

---

## Sign-off gate (before submitting)

- [ ] **All P0 pass**, core loop clean on **3 separate real meetings**.
- [ ] Report quality acceptable on real speech (avg ≥ 3/5) — else do the prompt-tuning pass.
- [ ] No crashes; offline pass (P0-8) clean.
- [ ] Voice: either hands-free meets latency, **or** decision made to ship push-to-talk only.
- [ ] P1 issues triaged (fix or defer to 1.0.1 with a note).

**Report results back** (which numbers failed + notes) and I'll turn each into a fix
commit the same day.
