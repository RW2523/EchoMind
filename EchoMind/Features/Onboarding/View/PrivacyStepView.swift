import SwiftUI

struct PrivacyStepView: View {
    var body: some View {
        VStack(spacing: 20) {
            BrandIconBadge(systemName: "lock.shield.fill", pulse: true)
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
