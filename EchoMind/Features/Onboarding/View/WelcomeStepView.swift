import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            BrandIconBadge(systemName: "waveform")
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
