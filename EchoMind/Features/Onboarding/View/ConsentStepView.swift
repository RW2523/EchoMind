import SwiftUI

struct ConsentStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            BrandIconBadge(systemName: "person.2.wave.2.fill", pulse: true)
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
