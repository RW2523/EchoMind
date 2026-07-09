import SwiftUI

/// Explains WHY mic + speech permissions will be requested. No system prompt
/// fires here — it's deferred to first recording (Phase 3) to maximize grant
/// rate and avoid a denied-at-onboarding dead end (§2.7).
struct PermissionPrimingStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            BrandIconBadge(systemName: "mic.badge.plus", pulse: true)
            Text("A couple of permissions")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                Label("Microphone — to capture what's said in your sessions.", systemImage: "mic.fill")
                Label("Speech Recognition — to transcribe it on-device.", systemImage: "text.bubble.fill")
            }
            .foregroundStyle(.secondary)
            Text("You'll be asked when you start your first recording — not now.")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
