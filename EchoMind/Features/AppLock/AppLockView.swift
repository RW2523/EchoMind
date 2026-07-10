import SwiftUI

/// Full-screen gate shown while the app is locked (F4). Auto-prompts once on
/// appear; the button re-prompts after a failed or cancelled attempt.
struct AppLockView: View {
    let controller: AppLockController

    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("EchoMind is locked")
                    .font(.title2.weight(.semibold))
                Button {
                    Task { await controller.unlock() }
                } label: {
                    Label("Unlock with \(controller.methodName)", systemImage: "faceid")
                        .font(.body.weight(.semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .task { await controller.unlock() }
    }
}
