import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Welcome to EchoMind")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("Private meeting memory for your iPhone: live transcription, saved sessions, and answers from your own knowledge — all on-device.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
