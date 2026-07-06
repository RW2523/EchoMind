import SwiftUI

struct ConsentStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.2.wave.2.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Recording responsibly")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(AppCopy.recordingConsent)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Tapping Continue means you understand.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
