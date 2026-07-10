import SwiftUI

/// Full-screen, hands-free voice conversation (ChatGPT/Grok-style). A living orb
/// carries the state, live captions show both sides of the exchange, and the whole
/// screen is the interrupt target: while the agent speaks, a tap cuts in. The
/// hands-free loop (listen → answer → listen) runs for as long as the screen is up.
struct VoiceConversationView: View {
    let voice: VoiceSessionController
    /// When true, the device only has default-quality system voices — offer a tip.
    var suggestBetterVoice: Bool = false
    let onClose: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("voiceQualityTipDismissed") private var tipDismissed = false

    private var mode: VoiceOrb.Mode {
        switch voice.state {
        case .idle: return .idle
        case .listening: return .listening
        case .thinking: return .thinking
        case .speaking: return .speaking
        case .failed: return .error
        }
    }

    /// A gentle live signal so the orb swells as you speak (transcript length proxy).
    private var level: Double {
        guard voice.state == .listening else { return 0 }
        return min(1, Double(voice.partialTranscript.count) / 90)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [DS.bg, Color(red: 0.02, green: 0.03, blue: 0.09)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
                VoiceOrb(mode: mode, level: level)
                    .frame(width: 240, height: 240)
                    .accessibilityHidden(true)
                statusLine
                    .padding(.top, 8)
                Spacer(minLength: 0)
                captions
                    .frame(maxHeight: 220)
                Spacer(minLength: 0)
                if suggestBetterVoice && !tipDismissed { voiceTip }
                controls
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
        // The screen is the interrupt surface while the agent is talking.
        .contentShape(Rectangle())
        .onTapGesture { if voice.state == .speaking || voice.state == .thinking { voice.bargeIn() } }
        .task { if !voice.isActive { await voice.startConversation() } }
        .onDisappear { voice.cancel() }
        .statusBarHidden(true)
    }

    private var header: some View {
        HStack {
            Text("Voice")
                .font(.headline).foregroundStyle(.white.opacity(0.9))
            Spacer()
            Button {
                voice.cancel()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.10), in: Circle())
            }
            .accessibilityLabel("Close voice")
        }
        .padding(.top, 8)
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.callout.weight(.medium))
            .foregroundStyle(.white.opacity(0.65))
            .contentTransition(.opacity)
            .animation(.easeInOut(duration: 0.25), value: statusText)
    }

    private var statusText: String {
        switch voice.state {
        case .idle: return "Starting…"
        case .listening: return voice.isHandsFree ? "Listening — just talk" : "Listening…"
        case .thinking: return "Thinking…"
        case .speaking: return "Tap anywhere to interrupt"
        case .failed(let message): return message
        }
    }

    @ViewBuilder private var captions: some View {
        VStack(spacing: 14) {
            // What you just said (dim, secondary).
            if !currentUserText.isEmpty {
                Text(currentUserText)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .transition(.opacity)
            }
            // The assistant's reply (bright, primary) as it streams.
            if !voice.spokenText.isEmpty {
                Text(voice.spokenText)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(6)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.25), value: voice.spokenText)
        .animation(.easeInOut(duration: 0.25), value: currentUserText)
        .accessibilityElement(children: .combine)
    }

    /// While listening, show the live partial; otherwise the finalized question.
    private var currentUserText: String {
        voice.state == .listening && !voice.partialTranscript.isEmpty
            ? voice.partialTranscript
            : voice.lastQuestion
    }

    /// One-time nudge to install a richer system voice. No deep-link — iOS has no
    /// public URL to the Voices page — so it just points the way, and dismisses.
    private var voiceTip: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "waveform.badge.plus")
                .foregroundStyle(DS.brandLight)
            Text("Want a more natural voice? Install one in **Settings ▸ Accessibility ▸ Spoken Content ▸ Voices**.")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button {
                withAnimation { tipDismissed = true }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.6))
            }
            .accessibilityLabel("Dismiss voice tip")
        }
        .padding(12)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 4)
        .padding(.bottom, 12)
        .transition(.opacity)
    }

    private var controls: some View {
        HStack(spacing: 40) {
            // Interrupt (only meaningful while the agent is talking/thinking).
            controlButton(system: "hand.raised.fill", label: "Interrupt",
                          tint: .white.opacity(0.9), bg: .white.opacity(0.12),
                          enabled: voice.state == .speaking || voice.state == .thinking) {
                voice.bargeIn()
            }
            // End the conversation.
            controlButton(system: "xmark", label: "End",
                          tint: .white, bg: Color(red: 0.85, green: 0.25, blue: 0.30),
                          enabled: true) {
                voice.cancel()
                onClose()
            }
        }
    }

    private func controlButton(system: String, label: String, tint: Color, bg: Color,
                               enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 64, height: 64)
                .background(bg, in: Circle())
                .opacity(enabled ? 1 : 0.35)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}
