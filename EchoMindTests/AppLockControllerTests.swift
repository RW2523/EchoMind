import Testing
import SwiftUI
@testable import EchoMind

/// F4: Face ID app lock. The controller's transitions are pinned here with a mock
/// authenticator; the real LAContext prompt is device-only.
@MainActor
private final class MockAuthenticator: AppLockAuthenticating {
    var isAvailable = true
    var methodName = "Face ID"
    var succeed = true
    private(set) var promptCount = 0

    func authenticate(reason: String) async -> Bool {
        promptCount += 1
        return succeed
    }
}

@MainActor
@Suite struct AppLockControllerTests {
    @Test func startsLockedWhenEnabled() {
        let controller = AppLockController(authenticator: MockAuthenticator(), isEnabled: { true })
        #expect(controller.isLocked)
    }

    @Test func startsUnlockedWhenDisabled() {
        let controller = AppLockController(authenticator: MockAuthenticator(), isEnabled: { false })
        #expect(!controller.isLocked)
    }

    @Test func successfulAuthUnlocks() async {
        let auth = MockAuthenticator()
        let controller = AppLockController(authenticator: auth, isEnabled: { true })
        await controller.unlock()
        #expect(!controller.isLocked)
        #expect(auth.promptCount == 1)
    }

    @Test func failedAuthStaysLocked() async {
        let auth = MockAuthenticator()
        auth.succeed = false
        let controller = AppLockController(authenticator: auth, isEnabled: { true })
        await controller.unlock()
        #expect(controller.isLocked)
    }

    @Test func backgroundRelocksOnlyWhenEnabled() async {
        let auth = MockAuthenticator()
        let controller = AppLockController(authenticator: auth, isEnabled: { true })
        await controller.unlock()
        controller.handleScenePhase(.background)
        #expect(controller.isLocked)

        let off = AppLockController(authenticator: auth, isEnabled: { false })
        off.handleScenePhase(.background)
        #expect(!off.isLocked)
    }

    @Test func inactiveDoesNotRelock() async {
        // The Face ID sheet itself makes the app .inactive — locking there would
        // re-lock mid-prompt. Only .background locks.
        let controller = AppLockController(authenticator: MockAuthenticator(), isEnabled: { true })
        await controller.unlock()
        controller.handleScenePhase(.inactive)
        #expect(!controller.isLocked)
    }

    @Test func settingTurnedOffWhileLockedUnlocksWithoutPrompt() async {
        var enabled = true
        let auth = MockAuthenticator()
        let controller = AppLockController(authenticator: auth, isEnabled: { enabled })
        enabled = false
        await controller.unlock()
        #expect(!controller.isLocked)
        #expect(auth.promptCount == 0)   // no prompt needed once disabled
    }

    @Test func unlockWhenAlreadyUnlockedDoesNotPrompt() async {
        let auth = MockAuthenticator()
        let controller = AppLockController(authenticator: auth, isEnabled: { false })
        await controller.unlock()
        #expect(auth.promptCount == 0)
    }
}
