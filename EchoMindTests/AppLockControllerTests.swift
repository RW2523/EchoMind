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

    @Test func failsOpenWhenDeviceCanNoLongerAuthenticate() async {
        // User enables the lock, then removes their device passcode: authentication
        // is impossible. A lock nobody can pass would brick the app (Settings — the
        // only way to disable it — is behind the lock), so it must fail open.
        let auth = MockAuthenticator()
        auth.isAvailable = false
        let atLaunch = AppLockController(authenticator: auth, isEnabled: { true })
        #expect(!atLaunch.isLocked)   // never locks at launch

        auth.isAvailable = true
        let controller = AppLockController(authenticator: auth, isEnabled: { true })
        #expect(controller.isLocked)
        auth.isAvailable = false      // passcode removed while locked
        await controller.unlock()
        #expect(!controller.isLocked)
        #expect(auth.promptCount == 0)   // opened without a prompt
    }

    @Test func autoPromptFiresOncePerLockCycle() async {
        // Cancelling the system prompt must NOT loop it — the lock screen's button
        // is the retry path. Re-locking (background) re-arms one automatic prompt.
        let auth = MockAuthenticator()
        auth.succeed = false          // simulate cancel/failure
        let controller = AppLockController(authenticator: auth, isEnabled: { true })

        await controller.autoUnlockIfNeeded()
        await controller.autoUnlockIfNeeded()   // e.g. scenePhase flaps to .active again
        #expect(auth.promptCount == 1)
        #expect(controller.isLocked)

        await controller.unlock()               // manual button still prompts
        #expect(auth.promptCount == 2)

        controller.handleScenePhase(.background)   // new lock cycle
        await controller.autoUnlockIfNeeded()
        #expect(auth.promptCount == 3)
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
