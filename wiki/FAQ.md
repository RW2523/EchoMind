# FAQ

**Is my data private?**
Yes. EchoMind makes **no network requests** and collects **no data**. Recordings,
transcripts, summaries, and notes stay in the app's encrypted, sandboxed storage on your
iPhone. There's no account and no analytics. This is enforced by an automated test
(`NetworkAuditTests`).

**How does the AI work without the cloud?**
Transcription uses Apple's on-device SpeechAnalyzer. Summaries, grouping, memory, and
answers use **Apple Intelligence** (Foundation Models) — all on the device.

**What iPhone do I need?**
An Apple-Intelligence-capable iPhone for the AI features. Transcription works more broadly.
A future update adds downloadable on-device models so full AI works even with Apple
Intelligence off (and on older iPhones).

**Do I need internet?**
No. Everything works in airplane mode. (The only time the app *could* use the network is if
you later download an optional on-device model, which is explicit and consent-gated.)

**Where are my recordings stored? Can I delete them?**
On your device only. Toggle "Keep audio recordings" in Settings. Delete individual sessions
by swiping, or wipe everything (sessions, audio, and memory) via **Settings ▸ Delete All
Data**. Export everything — Markdown transcripts *and* audio — via **Export All Data**.

**Why is a summary missing?**
It needs Apple Intelligence enabled (*Settings ▸ Apple Intelligence & Siri*). On unsupported
devices, transcription, playback, and export still work; you can generate the report when AI
is available.

**Recording stopped when I got a call — did I lose it?**
No. EchoMind pauses for interruptions and resumes; your transcript up to that point is saved.
Recording also survives the screen locking.

**Can I lock the app?**
Yes — turn on **Settings ▸ Require Face ID** and EchoMind locks whenever you leave it
(Face ID / Touch ID, passcode fallback). Biometric data is handled entirely by iOS;
the app never sees it.

**Why does EchoMind ask for Reminders access?**
Only if you tap **Add to Reminders** on a report — it writes those action items to
Apple Reminders and reads nothing back. Note the Reminders app follows your own
iCloud settings, so items you send there sync like any other reminder.

**What is "What EchoMind Remembers"?**
A long-term memory of durable facts (people, projects, decisions) EchoMind distills from your
meetings and uses to answer with context from every past meeting. You can see and delete any
fact in *Settings ▸ What EchoMind Remembers*.

**How does grouping decide categories?**
Meetings are clustered by concept using their embeddings (deterministic math), and the AI
only *names* each cluster — reusing an existing name so "Weekly Sync" and "Standup" don't
split into separate groups.

**Can I trust the summaries?**
They're AI-generated from your own speech. Quality depends on audio clarity and the model;
you can regenerate a report anytime. EchoMind never shares them — they're private notes.

**Is it on the App Store yet?**
Not yet. The app is build-ready; publishing requires an Apple Developer Program account and
a physical-device validation pass. See [TESTFLIGHT.md](https://github.com/RW2523/EchoMind/blob/main/AppStore/TESTFLIGHT.md).

**How do I contribute / build it?**
See the [README](Home) and [Architecture](Architecture). Build with Xcode 26+,
run tests serially with `-parallel-testing-enabled NO`.
