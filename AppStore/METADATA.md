# App Store Connect — EchoMind 1.0 metadata

Copy/paste into App Store Connect. All wording is truthful against the shipped 1.0
(on-device only, no data collected).

## Identity
- **Name:** EchoMind  *(check availability; fallbacks: "EchoMind — Meeting Memory", "EchoMind: Private Notes")*
- **Subtitle (30 char max):** Private AI meeting memory
- **Bundle ID:** com.ajace.EchoMind
- **Primary category:** Productivity   **Secondary:** Business
- **Age rating:** 4+
- **Price:** Free (1.0)

## Promotional text (170 char, updatable without review)
Record meetings and get instant on-device summaries, action items, and answers you
can ask by voice — all private, all on your iPhone. Nothing ever leaves your device.

## Description
Your meetings, remembered — privately.

EchoMind turns every meeting into searchable memory, without sending a single word
to the cloud. Record on your iPhone and EchoMind transcribes live, then Apple
Intelligence writes a clean report — summary, decisions, and action items — the
moment you stop.

WHAT ECHOMIND DOES
• Live transcription, fully on-device
• Automatic reports: summary, key decisions, and checkable action items
• Smart grouping: similar meetings are organized together automatically
• Total recall: EchoMind remembers people, projects, and decisions across every
  meeting — and uses that context when you ask
• Ask anything: chat with your meetings and documents, by text or by voice
• Tap any transcript line to play that moment of the recording
• Import PDFs and notes to search alongside your meetings

PRIVATE BY DESIGN
• 100% on-device — recordings, transcripts, and notes never leave your iPhone
• No account, no tracking, no third-party services
• Export or delete everything at any time

Powered by Apple Intelligence. Requires an iPhone with Apple Intelligence.

## Keywords (100 char, comma-separated, no spaces)
meeting,transcribe,notes,summary,recorder,voice,AI,transcript,private,action items,minutes,memo

## What's New (1.0)
First release. Record meetings, get instant on-device summaries and action items,
organize by topic, and ask your meetings anything — all private, all on-device.

## Support / Privacy URLs (required)
Live now, served by GitHub Pages from `docs/` (verified 200):
- **Privacy Policy URL:** https://rw2523.github.io/EchoMind/privacy.html
- **Support URL:** https://rw2523.github.io/EchoMind/support.html
- Marketing URL (optional): https://rw2523.github.io/EchoMind/

If you later publish these on ajace.com, update the two required URLs in App Store
Connect and keep the pages reachable — Apple re-checks them on every review.
(The earlier ajace.com/echomind/privacy + /support paths returned 404.)

## App Privacy questionnaire
- **Data collection: NONE.** Answer "No, we do not collect data from this app."
  (Provable: the app makes zero network calls — enforced by NetworkAuditTests.)
- Tracking: No.

## Export compliance
- Uses only standard OS encryption → exempt. `ITSAppUsesNonExemptEncryption=NO` is
  already in Info.plist, so no per-build prompt.

## Review notes (paste into "Notes")
EchoMind is a fully on-device meeting recorder and assistant. It makes NO network
requests of any kind; all AI (transcription via SpeechAnalyzer, summaries/answers
via Apple's Foundation Models) runs on the device.

Requirements: an Apple-Intelligence-capable iPhone with Apple Intelligence enabled
(Settings ▸ Apple Intelligence & Siri). On devices without it, recording/transcription
still work and the app clearly explains that AI summaries need Apple Intelligence.

Permissions: Microphone and Speech Recognition are core to the app (recording and
on-device transcription). Background audio mode keeps recording alive if the screen
locks during a meeting. Two optional permissions appear only if the user invokes the
feature: Face ID (Settings ▸ "Require Face ID" app lock) and Reminders (tapping
"Add to Reminders" on a report writes the report's action items to Apple Reminders;
the app never reads reminders).

To test AI without recording a meeting: open the **Ask** tab and ask a question — a
sample handbook is available so grounded answers work immediately. Or tap **Start
Live Transcript** to record.

## Screenshots (6.9" + 6.5", captions)
1. Home — "Your meetings, remembered — privately."
2. Live Transcript — "Transcribes live, 100% on-device."
3. Report — "Instant summaries & action items."
4. Sessions grouped — "Similar meetings, auto-organized."
5. Ask (chat) — "Ask your meetings anything."
6. Memory — "Remembers context across every meeting."
