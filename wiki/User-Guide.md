# User Guide

Everything EchoMind does, and how to use it. EchoMind is **100% on-device** — your
recordings, transcripts, and notes never leave your iPhone.

## Requirements

- An iPhone that supports **Apple Intelligence** (turn it on in *Settings ▸ Apple
  Intelligence & Siri*). Transcription works broadly; AI summaries and answers need Apple
  Intelligence.
- On first use, grant **Microphone** and **Speech Recognition** when prompted, and pick your
  **Transcription Language** in Settings (this installs the on-device speech model once).

## The screens

EchoMind has five tabs: **Home, Sessions, Knowledge, Ask, Settings.**

### Home
Your dashboard. Shows a live status card (Apple Intelligence readiness, "100% on-device",
and counts of your Sessions, meeting Types, and Memories), a big **Start Live Transcript**
button, quick actions, and your recent sessions.

### Recording a meeting
1. Tap **Start Live Transcript** (Home) or the **Sessions** flow.
2. Speak — your words appear live as they're transcribed. A waveform and timer show it's
   recording. Recording **continues if the screen locks** and pauses/resumes cleanly around
   phone calls and interruptions.
3. Tap **Stop**.

The moment you stop, EchoMind **automatically generates a report** in the background —
no button needed. The session also **names itself** from what was discussed (e.g.
"Q3 Launch Planning" instead of "Meeting Jul 9"); rename it anytime — your name
always wins and is never overwritten.

### Reports (auto)
Open a session (Sessions tab or Home ▸ Recent) to see its report:
- **Overview** — a few sentences on what the meeting covered.
- **Continuing from earlier meetings** — links to prior related meetings, when relevant.
- **Key Decisions**, **Risks**, **Open Questions**.
- **Action Items** — tap the circle to check one off; your checkmarks are saved
  (and survive regenerating the report). Tap **Add to Reminders** to send them to
  Apple Reminders, with the owner and source meeting in the notes.
- If Apple Intelligence isn't available, transcription still works and you can generate the
  report later with one tap.

### Playback (tap-to-play)
If "Keep audio recordings" is on (Settings, default on), the session detail shows a **player
bar**. Press play, drag the scrubber, or **tap any transcript line** to jump the audio to
that moment.

### Identify speakers *(optional)*
If the speaker-diarization pack is installed, a **⋯ ▸ Identify Speakers** action labels who
said what.

### Sessions — auto-grouped
The Sessions tab groups meetings by **AI category** (e.g. "Product Weekly", "1:1", "Customer
Call") with colored dots and counts. Use the **filter chips** at the top to show one
category. Search transcripts from the search bar. Swipe a session to delete it (its audio is
deleted too).

### Ask — chat with your meetings
The Ask tab is a chat. Ask a question in plain language ("What did we decide about the
launch?") and EchoMind answers from your meetings and documents, showing **Sources** you can
tap. It also carries **memory** — context from every past meeting — so follow-ups work
("Who owns onboarding?"). Tap the suggested follow-up chips to dig deeper.

**Ask by voice:**
- Tap the **mic** to speak a single question (push-to-talk); tap the check to finish.
  EchoMind answers *and speaks the reply aloud*.
- Tap the **waveform** button to open **Voice mode** — a full-screen, hands-free
  conversation. A glowing orb shows whether it's listening, thinking, or speaking; live
  captions show both sides. Just talk — it detects when you stop, answers, and listens
  again. **Tap anywhere (or the ✋) to interrupt.** Tap **✕** to end.
- The voice sounds best on devices with an enhanced or premium system voice (installed
  from *iOS Settings ▸ Accessibility ▸ Spoken Content ▸ Voices*). If the Kokoro voice
  pack is installed and selected, EchoMind uses its warmer voice instead.

### Knowledge — import documents
Import PDFs or text files with **+**. They become searchable in Ask alongside your meetings,
with sources pointing to the document and page.

### Settings
- **Apple Intelligence** — current status.
- **On-Device AI ▸ AI Models** — (when model packs are installed) download and choose
  on-device models.
- **On-Device AI ▸ What EchoMind Remembers** — see every durable fact EchoMind has learned,
  with its type; swipe to **forget** any fact.
- **Transcription Language** — pick your language / install its speech model.
- **Recording Audio** — toggle keeping audio recordings.
- **Privacy & Security** — **Require Face ID**: lock EchoMind whenever you leave it;
  unlock with Face ID / Touch ID (passcode fallback).
- **Storage** — how much space sessions, documents, index, and audio use.
- **Your Data** — **Export All Data** (Markdown per session, plus each session's
  audio recording) or **Delete All Data** (removes everything, including memory
  and audio).
- **About EchoMind** — version and privacy details.

## Privacy in practice

- Nothing is uploaded — EchoMind makes no network requests.
- No account, no sign-in, no analytics.
- Everything is stored encrypted on-device and can be exported or deleted anytime.
- Full policy: [PRIVACY_POLICY.md](https://github.com/RW2523/EchoMind/blob/main/AppStore/PRIVACY_POLICY.md).

## Troubleshooting

- **"Transcription isn't available for <language>"** — open *Settings ▸ Transcription
  Language*, select your language, and wait for the on-device model to download (needs Wi-Fi
  once).
- **No AI summary / "Requires Apple Intelligence"** — enable Apple Intelligence in iOS
  Settings; on unsupported devices, transcription and export still work.
- **Recording stopped during a call** — EchoMind pauses for interruptions and resumes; your
  transcript up to that point is saved.
- **Microphone access off** — the app shows an **Open Settings** button to re-enable it.
