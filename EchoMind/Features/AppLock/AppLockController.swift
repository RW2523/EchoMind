import SwiftUI

/// Lock-state machine for the Face ID app lock (F4). Locks at launch (when the
/// setting is on) and again whenever the app goes to background; unlocking runs
/// the system authentication prompt through the `AppLockAuthenticating` seam so
/// this whole object is unit-testable with a mock.
///
/// Deliberately locks only on `.background`, NOT `.inactive`: the Face ID sheet
/// itself makes the app `.inactive`, so locking there would re-lock mid-prompt.
@MainActor
@Observable
final class AppLockController {
    private(set) var isLocked: Bool
    /// True while the system prompt is up — guards double prompts when both the
    /// scene-phase change and the lock screen's auto-attempt fire.
    private var authenticating = false

    private let authenticator: any AppLockAuthenticating
    private let isEnabled: () -> Bool

    init(authenticator: any AppLockAuthenticating, isEnabled: @escaping () -> Bool) {
        self.authenticator = authenticator
        self.isEnabled = isEnabled
        self.isLocked = isEnabled()
    }

    var methodName: String { authenticator.methodName }

    func handleScenePhase(_ phase: ScenePhase) {
        guard isEnabled() else { isLocked = false; return }
        if phase == .background { isLocked = true }
    }

    /// Run the unlock prompt. No-op while a prompt is already up.
    func unlock() async {
        guard isLocked, !authenticating else { return }
        guard isEnabled() else { isLocked = false; return }
        authenticating = true
        defer { authenticating = false }
        if await authenticator.authenticate(reason: "Unlock EchoMind") {
            isLocked = false
        }
    }
}
