import SwiftUI

struct PrivacyStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Everything stays on this iPhone")
                .font(.title.bold())
                .multilineTextAlignment(.center)
            Text(AppCopy.privacyExplainer)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
